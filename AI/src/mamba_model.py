"""
MeltdownGuard-Mamba v2: TSCMamba 기반 경량 분류 모델 (순수 PyTorch 버전)
======================================================================
원본: https://github.com/Atik-Ahamed/TSCMamba

mamba-ssm 패키지 없이 순수 PyTorch로 Selective SSM을 구현.
DLPC 등 패키지 설치가 제한된 환경에서 사용.

데이터 흐름:
    [B, 5, 3840]
    → stem: Conv1d(5→64) + GELU + BN → [B, 64, 60]
    → permute → [B, 60, 64]
    → MambaBlock (시간 방향) → [B, 60, 64]
    → mean(dim=1) → [B, 64]
    → classifier → [B, num_class]
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import math


# ============================================================
# Pure PyTorch Mamba Block
# ============================================================
class MambaPure(nn.Module):
    """
    Selective State Space Model (S6) — 순수 PyTorch 구현.

    mamba-ssm의 Mamba 클래스와 동일한 인터페이스:
        입력: [B, L, D]  →  출력: [B, L, D]

    원리:
        1. 입력을 expand배로 확장 (d_inner = d_model * expand)
        2. 1D Conv로 로컬 컨텍스트 추출
        3. SSM 파라미터 (Δ, B, C) 를 입력으로부터 동적으로 생성 (Selective)
        4. 이산화된 SSM을 sequential scan으로 실행
        5. 게이트와 곱해서 출력
    """

    def __init__(self, d_model, d_state=16, d_conv=4, expand=2):
        super().__init__()
        self.d_model = d_model
        self.d_state = d_state
        self.d_conv = d_conv
        self.expand = expand
        self.d_inner = d_model * expand

        # 입력 투영: d_model → d_inner * 2 (x용 + gate용)
        self.in_proj = nn.Linear(d_model, self.d_inner * 2, bias=False)

        # 1D depthwise conv (로컬 컨텍스트)
        self.conv1d = nn.Conv1d(
            self.d_inner, self.d_inner,
            kernel_size=d_conv, padding=d_conv - 1,
            groups=self.d_inner, bias=True
        )

        # SSM 파라미터 투영
        self.x_proj = nn.Linear(self.d_inner, d_state * 2 + 1, bias=False)  # B, C, dt

        # dt (Δ) 파라미터
        self.dt_proj = nn.Linear(1, self.d_inner, bias=True)

        # A 파라미터 (고정 초기화, 학습 가능)
        A = torch.arange(1, d_state + 1, dtype=torch.float32).unsqueeze(0).expand(self.d_inner, -1)
        self.A_log = nn.Parameter(torch.log(A))

        # D 파라미터 (skip connection)
        self.D = nn.Parameter(torch.ones(self.d_inner))

        # 출력 투영
        self.out_proj = nn.Linear(self.d_inner, d_model, bias=False)

    def forward(self, x):
        """
        Args:
            x: [B, L, D]
        Returns:
            out: [B, L, D]
        """
        B, L, D = x.shape

        # 1. 입력 투영 → [B, L, d_inner*2]
        x_and_gate = self.in_proj(x)
        x_inner, gate = x_and_gate.chunk(2, dim=-1)

        # 2. 1D Conv (시간축)
        x_conv = x_inner.transpose(1, 2)
        x_conv = self.conv1d(x_conv)[:, :, :L]
        x_conv = x_conv.transpose(1, 2)
        x_conv = F.silu(x_conv)

        # 3. SSM 파라미터 생성 (Selective)
        ssm_params = self.x_proj(x_conv)
        B_param = ssm_params[:, :, :self.d_state]
        C_param = ssm_params[:, :, self.d_state:self.d_state*2]
        dt_raw = ssm_params[:, :, -1:]

        dt = F.softplus(self.dt_proj(dt_raw))

        A = -torch.exp(self.A_log)

        # 4. Selective Scan
        y = self._selective_scan(x_conv, dt, A, B_param, C_param)

        # Skip connection
        y = y + x_conv * self.D.unsqueeze(0).unsqueeze(0)

        # 5. Gate 적용
        y = y * F.silu(gate)

        # 6. 출력 투영
        out = self.out_proj(y)
        return out

    def _selective_scan(self, x, dt, A, B_param, C_param):
        """
        이산화된 SSM의 sequential scan.

        h(t) = A_bar * h(t-1) + B_bar * x(t)
        y(t) = C(t) * h(t)
        """
        B_batch, L, d_inner = x.shape

        dt_A = dt.unsqueeze(-1) * A.unsqueeze(0).unsqueeze(0)
        A_bar = torch.exp(dt_A)

        B_bar = dt.unsqueeze(-1) * B_param.unsqueeze(2)

        h = torch.zeros(B_batch, d_inner, self.d_state, device=x.device, dtype=x.dtype)
        ys = []

        for t in range(L):
            h = A_bar[:, t] * h + B_bar[:, t] * x[:, t].unsqueeze(-1)
            y_t = (C_param[:, t].unsqueeze(1) * h).sum(dim=-1)
            ys.append(y_t)

        y = torch.stack(ys, dim=1)
        return y


# ============================================================
# Model
# ============================================================
class Model(nn.Module):
    """MeltdownGuard-Mamba v2 (순수 PyTorch)."""

    def __init__(self, configs):
        super(Model, self).__init__()
        self.configs = configs

        # ① Stem
        self.stem = nn.Sequential(
            nn.Conv1d(
                in_channels=configs.enc_in,
                out_channels=configs.projected_space,
                kernel_size=configs.patch_len,
                stride=configs.patch_len
            ),
            nn.GELU(),
            nn.BatchNorm1d(configs.projected_space)
        )

        self.dropout = nn.Dropout(configs.dropout)

        # ② Mamba Backbone (순수 PyTorch)
        self.mamba_blocks = nn.ModuleList([
            MambaPure(
                d_model=configs.projected_space,
                d_state=configs.d_state,
                d_conv=configs.dconv,
                expand=configs.e_fact
            ) for _ in range(configs.num_mambas)
        ])

        # ③ Classification Head
        self.classifier = nn.Sequential(
            nn.Linear(configs.projected_space, configs.projected_space // 2),
            nn.GELU(),
            nn.Dropout(configs.dropout),
            nn.Linear(configs.projected_space // 2, configs.num_class)
        )

    def forward(self, x):
        x = self.stem(x)
        x = x.permute(0, 2, 1)

        if self.configs.num_mambas != 0:
            x1 = x
            for mamba in self.mamba_blocks:
                x1 = mamba(x1) + x1

            if self.configs.only_forward_scan == 0:
                x_flipped = torch.flip(x, dims=[1])
                x1_flipped = x_flipped
                for mamba in self.mamba_blocks:
                    x1_flipped = mamba(x1_flipped) + x1_flipped

                if self.configs.reverse_flip == 1:
                    x1 = x1 + torch.flip(x1_flipped, dims=[1])
                else:
                    x1 = x1 + x1_flipped

            x = x1

        x = self.dropout(x)
        x = x.mean(dim=1)
        logits = self.classifier(x)
        return logits

    def count_parameters(self):
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ============================================================
# Config
# ============================================================
class MeltdownGuardConfig:
    def __init__(self, **kwargs):
        self.enc_in = kwargs.get('enc_in', 9)
        self.seq_len = kwargs.get('seq_len', 3840)
        self.num_class = kwargs.get('num_class', 3)

        self.projected_space = kwargs.get('projected_space', 64)
        self.d_state = kwargs.get('d_state', 16)
        self.dconv = kwargs.get('dconv', 4)
        self.e_fact = kwargs.get('e_fact', 2)
        self.num_mambas = kwargs.get('num_mambas', 1)
        self.dropout = kwargs.get('dropout', 0.3)
        self.patch_len = kwargs.get('patch_len', 64)

        self.only_forward_scan = kwargs.get('only_forward_scan', 1)  # 1=tango OFF
        self.reverse_flip = kwargs.get('reverse_flip', 1)

        self.task_name = 'classification'


def create_model(config_dict=None):
    config = MeltdownGuardConfig(**(config_dict or {}))
    model = Model(config)
    return model, config


# ============================================================
# 테스트
# ============================================================
if __name__ == '__main__':
    print("=" * 55)
    print("  MeltdownGuard-Mamba v2 (순수 PyTorch) 테스트")
    print("=" * 55)

    model, config = create_model()
    dummy = torch.randn(4, 9, 3840)
    output = model(dummy)

    print(f"\n  입력:  {dummy.shape}")
    print(f"  출력:  {output.shape}")
    print(f"  파라미터: {model.count_parameters():,}")
    print(f"  Tango: {'ON' if config.only_forward_scan == 0 else 'OFF'}")

    print(f"\n  shape 추적:")
    with torch.no_grad():
        x = dummy
        x = model.stem(x)
        print(f"  stem 후:    {x.shape}")
        x = x.permute(0, 2, 1)
        print(f"  permute 후: {x.shape}")
        for mamba in model.mamba_blocks:
            x = mamba(x) + x
        print(f"  mamba 후:   {x.shape}")
        x = x.mean(dim=1)
        print(f"  pooling 후: {x.shape}")

    print(f"\n✅ 테스트 완료! (mamba-ssm 불필요)")
