"""
MeltdownGuard-Mamba v2: TSCMamba 기반 경량 분류 모델 (순수 PyTorch 버전)
======================================================================
원본: https://github.com/Atik-Ahamed/TSCMamba

mamba-ssm 패키지 없이 순수 PyTorch로 Selective SSM을 구현.
DLPC 등 패키지 설치가 제한된 환경에서 사용.

데이터 흐름:
    [B, 9, 1500]  <- Galaxy Watch 8 25Hz Update
    → stem: Conv1d(5→64) + GELU + BN → [B, 64, 30]
    → permute → [B, 30, 64]
    → MambaBlock (시간 방향) → [B, 30, 64]
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
    def __init__(self, d_model, d_state=16, d_conv=4, expand=2):
        super().__init__()
        self.d_model = d_model
        self.d_state = d_state
        self.d_conv = d_conv
        self.expand = expand
        self.d_inner = d_model * expand

        self.in_proj = nn.Linear(d_model, self.d_inner * 2, bias=False)
        self.conv1d = nn.Conv1d(
            self.d_inner, self.d_inner,
            kernel_size=d_conv, padding=d_conv - 1,
            groups=self.d_inner, bias=True
        )
        self.x_proj = nn.Linear(self.d_inner, d_state * 2 + 1, bias=False)  
        self.dt_proj = nn.Linear(1, self.d_inner, bias=True)

        A = torch.arange(1, d_state + 1, dtype=torch.float32).unsqueeze(0).expand(self.d_inner, -1)
        self.A_log = nn.Parameter(torch.log(A))
        self.D = nn.Parameter(torch.ones(self.d_inner))
        self.out_proj = nn.Linear(self.d_inner, d_model, bias=False)

    def forward(self, x):
        B, L, D = x.shape

        x_and_gate = self.in_proj(x)
        x_inner, gate = x_and_gate.chunk(2, dim=-1)

        x_conv = x_inner.transpose(1, 2)
        x_conv = self.conv1d(x_conv)[:, :, :L]
        x_conv = x_conv.transpose(1, 2)
        x_conv = F.silu(x_conv)

        ssm_params = self.x_proj(x_conv)
        B_param = ssm_params[:, :, :self.d_state]
        C_param = ssm_params[:, :, self.d_state:self.d_state*2]
        dt_raw = ssm_params[:, :, -1:]

        dt = F.softplus(self.dt_proj(dt_raw))
        A = -torch.exp(self.A_log)

        y = self._selective_scan(x_conv, dt, A, B_param, C_param)
        y = y + x_conv * self.D.unsqueeze(0).unsqueeze(0)
        y = y * F.silu(gate)

        out = self.out_proj(y)
        return out

    def _selective_scan(self, x, dt, A, B_param, C_param):
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
    def __init__(self, configs):
        super(Model, self).__init__()
        self.configs = configs

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

        self.mamba_blocks = nn.ModuleList([
            MambaPure(
                d_model=configs.projected_space,
                d_state=configs.d_state,
                d_conv=configs.dconv,
                expand=configs.e_fact
            ) for _ in range(configs.num_mambas)
        ])

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
        self.seq_len = kwargs.get('seq_len', 1500) # Updated for 25Hz x 60s
        self.num_class = kwargs.get('num_class', 2)

        self.projected_space = kwargs.get('projected_space', 64)
        self.d_state = kwargs.get('d_state', 16)
        self.dconv = kwargs.get('dconv', 4)
        self.e_fact = kwargs.get('e_fact', 2)
        self.num_mambas = kwargs.get('num_mambas', 1)
        self.dropout = kwargs.get('dropout', 0.3)
        self.patch_len = kwargs.get('patch_len', 50) # Updated for clean division of 1500

        self.only_forward_scan = kwargs.get('only_forward_scan', 1) 
        self.reverse_flip = kwargs.get('reverse_flip', 1)

        self.task_name = 'classification'

def create_model(config_dict=None):
    config = MeltdownGuardConfig(**(config_dict or {}))
    model = Model(config)
    return model, config

if __name__ == '__main__':
    print("=" * 55)
    print("  MeltdownGuard-Mamba v2 (Galaxy Watch 8 Target) 테스트")
    print("=" * 55)

    model, config = create_model()
    dummy = torch.randn(4, 9, 1500)
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
