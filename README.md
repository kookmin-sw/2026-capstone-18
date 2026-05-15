<p align="center">
  <img src="docs/images/luma-wordmark.svg" alt="Luma" width="480"/>
</p>

# Luma — 2026 Capstone 18

[![Total commits](https://img.shields.io/github/commit-activity/t/kookmin-sw/2026-capstone-18)](https://github.com/kookmin-sw/2026-capstone-18/commits/master)
[![Last commit](https://img.shields.io/github/last-commit/kookmin-sw/2026-capstone-18)](https://github.com/kookmin-sw/2026-capstone-18/commits/master)
[![Commit activity](https://img.shields.io/github/commit-activity/m/kookmin-sw/2026-capstone-18)](https://github.com/kookmin-sw/2026-capstone-18/pulse)
[![Contributors](https://img.shields.io/github/contributors/kookmin-sw/2026-capstone-18)](https://github.com/kookmin-sw/2026-capstone-18/graphs/contributors)
[![License](https://img.shields.io/github/license/kookmin-sw/2026-capstone-18)](LICENSE)
[![Stars](https://img.shields.io/github/stars/kookmin-sw/2026-capstone-18?style=flat)](https://github.com/kookmin-sw/2026-capstone-18/stargazers)

<p align="center">
  <video src="https://github.com/user-attachments/assets/9077115f-dcfc-4898-a309-afc126edbf79" controls muted playsinline width="320"></video>
</p>

![AWS Seoul (ap-northeast-2) architecture](docs/images/architecture.png)

여성 사용자를 위한 실시간 스트레스 탐지 및 생리 주기 추적 애플리케이션입니다. Galaxy Watch 8에서 수집한 생체신호(PPG, EDA, HRV, 가속도)를 스마트폰 온디바이스(Mamba) 환경에서 분석하여 스트레스 이벤트를 탐지하며, 감지 결과를 앱 UI에 표시하고 필요한 경우 스트레스 기록 흐름으로 연결합니다. 백엔드는 AWS 서울 리전(ap-northeast-2)에 배포되어 있으며, 한국의 개인정보보호법(PIPA)을 준수하도록 설계되었습니다.

- **팀**: 국민대학교 2026 캡스톤 18조
- **팀페이지**: <https://kookmin-sw.github.io/2026-capstone-18/>
- **타깃 플랫폼**: Galaxy Watch 8 (Wear OS) + Android (Flutter)
- **배포 리전**: AWS Seoul (`ap-northeast-2`)

### 기술 스택

**Backend**
![Python](https://img.shields.io/badge/Python_3.12-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI_0.136-009688?logo=fastapi&logoColor=white)
![SQLAlchemy](https://img.shields.io/badge/SQLAlchemy_2.0-D71F00?logo=sqlalchemy&logoColor=white)
![Pydantic](https://img.shields.io/badge/Pydantic_v2-E92063?logo=pydantic&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL_15-4169E1?logo=postgresql&logoColor=white)
![Poetry](https://img.shields.io/badge/Poetry-60A5FA?logo=poetry&logoColor=white)
![Wear OS](https://img.shields.io/badge/Wear_OS-4285F4?logo=wearos&logoColor=white)

**Cloud / Infra**
![AWS](https://img.shields.io/badge/AWS_Seoul-232F3E?logo=amazonwebservices&logoColor=white)
![ECS](https://img.shields.io/badge/ECS_Fargate-FF9900?logo=amazonecs&logoColor=white)
![RDS](https://img.shields.io/badge/RDS-527FFF?logo=amazonrds&logoColor=white)
![S3](https://img.shields.io/badge/S3-569A31?logo=amazons3&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3FCF8E?logo=supabase&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)

**AI / ML**
![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?logo=pytorch&logoColor=white)
![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-005CED?logo=onnx&logoColor=white)
![NumPy](https://img.shields.io/badge/NumPy-013243?logo=numpy&logoColor=white)
![Pandas](https://img.shields.io/badge/Pandas-150458?logo=pandas&logoColor=white)
![Jupyter](https://img.shields.io/badge/Jupyter-F37626?logo=jupyter&logoColor=white)

**Frontend / Watch**
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Kotlin](https://img.shields.io/badge/Kotlin-7F52FF?logo=kotlin&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)
![Gradle](https://img.shields.io/badge/Gradle-02303A?logo=gradle&logoColor=white)

**Quality / Tooling**
![Ruff](https://img.shields.io/badge/Ruff-D7FF64?logo=ruff&logoColor=black)
![mypy](https://img.shields.io/badge/mypy_strict-2A6DB2?logo=python&logoColor=white)
![pytest](https://img.shields.io/badge/pytest-0A9EDC?logo=pytest&logoColor=white)
![Sentry](https://img.shields.io/badge/Sentry-362D59?logo=sentry&logoColor=white)
![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-000000?logo=opentelemetry&logoColor=white)

---

## 목차

- [저장소 구조](#저장소-구조)
- [선행 요구사항](#선행-요구사항)
- [1. AI — 스트레스 탐지 (Mamba)](#1-ai--스트레스-탐지-mamba)
  - [1.1 주요 기술 결정](#11-주요-기술-결정)
  - [1.2 9-채널 입력 텐서 매핑](#12-9-채널-입력-텐서-매핑)
  - [1.3 빠른 시작](#13-빠른-시작)
- [2. Backend — FastAPI on AWS Seoul](#2-backend--fastapi-on-aws-seoul)
  - [2.1 설계 원칙](#21-설계-원칙)
  - [2.2 기술 스택](#22-기술-스택)
  - [2.3 인프라 (Terraform)](#23-인프라-terraform)
  - [2.4 데이터 모델 (요약)](#24-데이터-모델-요약)
  - [2.5 API 요약](#25-api-요약)
  - [2.6 로컬 개발](#26-로컬-개발)
  - [2.7 스테이징 배포](#27-스테이징-배포)
  - [2.8 Agentic AI — Bedrock + Claude Haiku 4.5](#28-agentic-ai--bedrock--claude-haiku-45)
- [3. Wear OS — Galaxy Watch 8 센서 캡처](#3-wear-os--galaxy-watch-8-센서-캡처)
  - [3.1 캡처 채널](#31-캡처-채널)
  - [3.2 SDK 검증 결과 (2026-05-04)](#32-sdk-검증-결과-2026-05-04)
  - [3.3 출력 레이아웃](#33-출력-레이아웃)
  - [3.4 빌드와 실행](#34-빌드와-실행)
  - [3.5 데이터 추출](#35-데이터-추출)
- [4. Frontend — Flutter Android App](#4-frontend--flutter-android-app)
  - [4.1 Frontend 개요](#41-frontend-개요)
  - [4.2 설계 목표](#42-설계-목표)
  - [4.3 기술 스택](#43-기술-스택)
  - [4.4 구현된 주요 기능](#44-구현된-주요-기능)
  - [4.5 Architecture 요약](#45-architecture-요약)
  - [4.6 사용자 흐름](#46-사용자-흐름)
  - [4.7 Frontend Data Flow](#47-frontend-data-flow)
  - [4.8 Backend Integration](#48-backend-integration)
  - [4.9 Native Capture Integration](#49-native-capture-integration)
  - [4.10 Notification Flow](#410-notification-flow)
  - [4.11 Frontend 실행과 테스트](#411-frontend-실행과-테스트)
- [5. 아키텍처 전체 흐름 (요약)](#5-아키텍처-전체-흐름-요약)
- [6. 문서](#6-문서)
- [7. 팀 소개](#7-팀-소개)
- [8. 시연 영상](#8-시연-영상)
- [기여 가이드](#기여-가이드)
- [라이선스](#라이선스)

---

## 저장소 구조

```text
2026-capstone-18/
├── AI/                       # 스트레스 탐지 Mamba 파이프라인 (학습/평가, 60s 윈도우 이진 분류)
│   ├── notebooks/
│   └── src/
│       ├── dataset/          # WESAD / Stress-Predict 다운로드·전처리
│       ├── mamba_model.py    # Pure PyTorch Mamba 아키텍처
│       ├── pipeline.py       # 학습·평가 공용 전처리/추론 헬퍼
│       ├── train_kfold.py    # 5-Fold GroupKFold 학습 루프
│       ├── train_LOSO.py     # Leave-One-Subject-Out 검증
│       └── train_final_model.py # 배포용 단일 모델 학습 (Hold-out validation)
├── backend/                  # FastAPI 백엔드 + Terraform 인프라
│   ├── app/                  # 라우터·서비스·모델·스키마·관측성
│   ├── alembic/              # DB 마이그레이션
│   ├── infra/                # Terraform (ECS, RDS, ALB, S3, EventBridge)
│   ├── scripts/              # 부트스트랩·마이그레이션·스모크 테스트
│   └── docs/                 # 스프린트별 배포 런북
├── frontend/                 # Flutter Android 앱 + Kotlin native capture/inference layer
│   ├── lib/                  # Dart UI, providers, feature data layer
│   └── android/app/src/main/kotlin/com/littlesignals/app/  # capture/, inference/ (ONNX), notifications/
├── watch/
│   └── sensor-capture/       # Wear OS 원시 센서 수집 유틸 (Kotlin)
├── README.md
└── index.md                  # GitHub Pages 진입점
```

---

## 선행 요구사항

전체 시스템(AI 학습 → 백엔드 → Watch → Flutter 앱)을 로컬·스테이징에서 구동하려면 다음 계정·도구·하드웨어가 필요합니다. 각 영역만 단독으로 실행할 때 필요한 항목은 하단 "필수 영역" 열을 참고하세요.

| 분류 | 항목 | 용도 | 필수 영역 | 비용 (베타 코호트 기준) |
| :--- | :--- | :--- | :--- | :--- |
| 클라우드 | **AWS 계정 (Seoul `ap-northeast-2`)** | ECS Fargate, RDS Postgres 15, ALB, S3, EventBridge, Secrets Manager, CloudWatch, SQS, ECR, Route53, ACM | Backend 배포 | Free Tier + 소액 사용량 |
| 인증 | **Supabase 프로젝트** | JWT 발급, 익명 사용자, Google OAuth 교환 | Backend, Frontend | Free Tier |
| 푸시 | **Firebase 프로젝트** | Cloud Messaging(FCM) 토큰 등록 + 백그라운드 푸시 | Backend, Frontend | Free |
| OAuth | **Google Cloud 프로젝트** (OAuth 클라이언트) | Supabase Auth와 연동되는 Google 로그인 | Frontend | Free |
| 도메인 | 사용자 소유 도메인 1개 | 스테이징 ACM/Route53 (`api-staging.<도메인>`) | Backend 배포 | 기존 도메인 재사용 |
| CI/CD | **GitHub** (조직 권한) | GitHub Actions로 ECR 푸시·Terraform plan·마이그레이션 실행 | 전 영역 | Public 저장소 무료 |
| 로컬 도구 | Python 3.12 (pyenv), Poetry 2.x, Docker Desktop, `psql`, `jq` | 백엔드 로컬 개발/테스트 | Backend | — |
| 로컬 도구 | Terraform 1.7+, AWS CLI v2 | 인프라 프로비저닝 | Backend 배포 | — |
| 로컬 도구 | Flutter SDK (stable), Android Studio Iguana 이상, Android SDK 34+ | Phone 앱 빌드 | Frontend | — |
| 로컬 도구 | Android Studio + Wear OS 에뮬레이터/실기기, `adb` | Watch 캡처 도구 빌드 | Watch | — |
| 하드웨어 | **Galaxy Watch 8** (개발자 모드, 80% 이상 충전) | 4채널 원시 센서 캡처 + Wear Data Layer로 폰 실시간 스트리밍 | Watch | — |
| 하드웨어 | Android 폰 (Galaxy Z Flip 5 등) | Flutter 앱 실기기 테스트 | Frontend | — |
| SDK | Samsung Health Sensor SDK 1.4.1 (`samsung-health-sensor-api-1.4.1.aar`) | Watch 센서 채널 접근 | Watch | 저장소에 포함 |

각 도구의 정확한 버전 핀은 `backend/pyproject.toml`, `backend/infra/main.tf` (`terraform { required_version = ">= 1.7.0" }`), `frontend/pubspec.yaml`, `watch/sensor-capture/build.gradle.kts`에서 확인합니다.

---

## AI — 생체신호 기반 스트레스 탐지 파이프라인

WESAD 및 StressPredict 데이터셋을 통합 활용하여 연속적인 생체신호(PPG, EDA, ACC)로부터 스트레스 상태를 탐지하는 시계열 분류(TSC) 파이프라인입니다. 본 시스템의 목적은 일상생활 중 발생하는 스트레스 이벤트를 감지하고, 온디바이스 환경에서 감지 신호를 앱 UI와 스트레스 기록 흐름으로 연결하는 것입니다.

![Stress ML demo pipeline — 9-stage 검증 다이어그램 (오프라인 zip 입력 → ONNX → per-chunk JSON 출력)](docs/images/ml-demo.png)

> ℹ️ 위 다이어그램은 *오프라인 검증 경로*(서버에 zip을 업로드해 모델 출력 회귀를 확인하는 데모 도구)를 보여줍니다. 현재 실제 운영 경로는 §1과 §5의 다이어그램을 따르며 워치 → 폰 스트리밍 + 폰 온디바이스 추론으로 동작합니다.

### 1. 시스템 아키텍처 (On-Device Inference)
데이터의 수집부터 추론, 이벤트 생성, 알림 인프라까지의 과정은 개인정보보호(PIPA)를 고려해 설계되었습니다.
* **Galaxy Watch (Sensor Node):** Samsung Health Sensor SDK로 Heart rate/IBI, PPG green, EDA, Accelerometer 채널을 수집하고, phone-driven streaming mode에서는 Wear Data Layer(`/biosignals/start`, `/biosignals/stop`, `/biosignals/samples`)로 스마트폰에 sample batch를 실시간 전달합니다. 워치 내부에서는 ML 추론이 발생하지 않으며, 동일 APK는 모델 검증용 standalone 10분 ZIP export mode도 제공합니다.
* **Smartphone App (Inference & Decision Engine):** 스마트폰의 Android-native 레이어(Kotlin + `onnxruntime-android` 1.18.0)에서 Mamba 모델이 온디바이스로 실행됩니다. 60초 슬라이딩 윈도(300s 버퍼) 단위로 추론을 수행하고, 모션 게이트·쿨다운 기반 결정 로직으로 감지 결과 표시와 이벤트 기록 여부를 판단합니다. 결과는 Flutter UI에 platform channel(`littlesignals/capture/detections`)로 전달되어 카드 형태로 표시되며, 동시에 백엔드 `POST /api/v1/events`로 기록됩니다.
* **Backend Server (Privacy Logging):** 최종 스트레스 이벤트 로그와 메타데이터가 서버로 전송됩니다. 사용자가 원시 생체신호 업로드에 동의한 경우에만 Android Keystore 기반 AES-256-GCM으로 암호화된 ciphertext window가 S3에 업로드되며, 평문 원시 생체신호와 복호화 키는 사용자 기기 밖으로 나가지 않습니다.

---

### 2. 데이터셋 엔지니어링 및 전처리 (Unified Binary Classification)
다양한 환경의 생체신호를 학습하기 위해 WESAD(통제 환경)와 StressPredict(일상/Ambulatory 환경) 데이터셋을 이진 분류(Baseline vs. Stress) 태스크로 통합했습니다. 휴식, 명상, 즐거움 등의 상태는 모두 Class 0(Baseline)으로 매핑됩니다.

**2.1 비대칭 학습 및 평가 전략 (Asymmetric Setup)**
타겟 사용자층에 맞춘 견고한 증명을 위해 비대칭 스플릿을 적용했습니다.
* **Training Split (정규화 및 다양성):** 전체 WESAD(15명) 및 StressPredict(35명) 피험자를 모두 학습에 포함하여 생물학적 다양성과 정규화 효과를 확보했습니다.
* **Evaluation Split (타겟 검증):** 모델이 타겟 인구통계에서 안정적으로 작동하는지 확인하기 위해, 여성 비율이 압도적으로 높은 분할(WESAD 여성 피험자 + StressPredict 전체)을 구성하여 검증했습니다.
* **Deployment Model Selection:** K-Fold 평균에 의존하지 않고, 모델 안정성을 확인하기 위해 가장 대표적인 피험자 5명(WESAD 1명, StressPredict 4명)을 Hold-out Validation으로 분리해 최종 배포 모델을 선정했습니다.

**2.2 텐서 아키텍처 및 9-채널 입력 (`[Batch, 9, 1500]`)**
Galaxy Watch 8 SDK 출력에 맞춰 25Hz 목표 주파수로 동기화된 60초 입력 윈도우를 사용합니다. 현재 앱의 실시간 추론·업로드 경로는 1분 단위 window cadence로 동작합니다. 아래 피처명은 온디바이스 추론 시점의 채널 배열 순서(`StressPipeline.kt`의 9-channel layout)이며, 학습용 `AI/src/dataset/` 전처리는 동일한 의미의 텐서를 익명 인덱스 순서로 출력합니다.

| 인덱스 | 피처명 | 설명 및 연산 방식 |
| :---: | :--- | :--- |
| **0** | `ppg_calib` | 4차 Butterworth 및 Savitzky-Golay 필터링된 PPG 신호 (Z-Score) |
| **1** | `eda_calib` | 절대 피부 전도도 (Z-Score) |
| **2** | `acc_global` | 전역 물리적 활동량 (1g 휴식 기준 매핑, [-3.0, 3.0] 클리핑) |
| **3** | `eda_ema_context` | 300초(5분) Causal EMA (EDA 거시 추세) |
| **4** | `bvp_ema_context` | 300초(5분) Causal EMA (PPG 거시 추세) |
| **5** | `eda_macd` | EDA Phasic 변화량 (10s EMA - 60s EMA) |
| **6** | `bvp_macd` | PPG Phasic 변화량 (10s EMA - 60s EMA) |
| **7** | `norm_std_eda` | 300초 후행 EDA 노이즈 분산 (Log-compressed, Z-Score) |
| **8** | `norm_std_bvp` | 300초 후행 PPG 노이즈 분산 (Log-compressed, Z-Score) |

**2.3 최종 클래스 분포**
* **Full Training Pool:** 총 38,742 Chunks (~53.8 시간) | Class 0: 75.87% / Class 1: 24.13%
* **Evaluation Pool:** 총 25,322 Chunks (~35.2 시간) | Class 0: 69.32% / Class 1: 30.68%

---

### 3. 모델 아키텍처 및 학습
엣지 환경에서의 원활한 ONNX 변환 및 CPU 추론을 위해, `mamba-ssm`의 CUDA 커널 의존성을 제거한 순수 PyTorch 기반 Selective SSM을 설계했습니다.

**3.1 차원 축소 및 흐름**
1. **Conv1d Stem:** `[Batch, 9, 1500]` 크기의 입력은 Kernel/Stride가 50인 1D 합성곱을 통과하여 지역적 특징을 추출하고 `[Batch, 64, 30]`으로 공격적인 다운샘플링을 수행합니다.
2. **Selective SSM (MambaPure):** `[Batch, 30, 64]`로 Permute된 텐서는 $d\_state=16$, $dconv=4$로 설정된 Mamba 블록을 통과하며 시간적 의존성을 모델링합니다. (연산량 최소화를 위해 Forward-only 스캔 채택).
3. **Global Pooling & Classifier:** `mean(dim=1)` 풀링으로 시간 차원을 압축한 후, 두 개의 선형 계층(64 -> 32 -> 2)을 거쳐 최종 이진 Logit을 출력합니다.

**3.2 인스턴스 가중치 초점 손실 (Instance-Weighted Focal Loss)**
데이터셋 간의 노이즈 차이와 클래스 불균형을 극복하기 위해, 예측이 쉬운 Baseline Chunk의 그래디언트 기여도를 억제하는 Focal Loss($\gamma=3.0$)를 적용했습니다.

$$L = \frac{1}{N} \sum_{i=1}^{N} w_i \cdot (1 - p_{t,i})^3 \cdot \text{CE}(x_i, y_i)$$

통제 환경(WESAD)에서 명확하게 라벨링된 Stress 이벤트의 분류 손실에 가장 큰 수학적 페널티를 부여해 라벨 노이즈가 적은 신호에서 결정 경계를 우선 학습시키도록 그리드 서치 기반 가중치($w_i$)를 적용했습니다. StressPredict는 일상/Ambulatory 환경 노이즈가 크기 때문에 두 클래스 모두 동일한 1.0 가중치를 부여합니다 (`AI/src/train_kfold.py:34-51`, CLI 기본값 `--wesad_stress_w 2.0`).
* **WESAD Baseline:** 0.5
* **WESAD Stress:** 2.0
* **StressPredict Baseline:** 1.0
* **StressPredict Stress:** 1.0

---

### 4. 스트레스 감지 결정 엔진
단순한 Softmax 확률값에 의존하지 않고, False Alarms으로 인한 사용자 피로도를 극단적으로 낮추기 위해 4단계 UX 상태 머신 필터를 적용합니다.

* **Confidence Threshold:** 모델의 스트레스 확률값이 60% 이상일 때만 활성화.
* **Motion Artifact Rejection (MAR 0.10):** 60초 구간의 평균 가속도 크기가 0.10을 초과하면 움직임 노이즈로 간주하여 확률값과 무관하게 스트레스 판정 기각.
* **Gap Bridging (120s):** 신호 단절을 보정하기 위해, 120초(2 Chunks) 연속 평상시 상태가 유지되어야 스트레스 이벤트가 종료된 것으로 간주.
* **Notification Cooldown (300s):** 알림 피로도 방지를 위해 감지 신호 발생 후 5분간 추가 신호 차단.

---

### 5. 성능 평가 및 UX 지표
모델 평가는 단순한 Chunk 단위의 F1-Score를 넘어 실제 스마트워치 알림의 품질을 대변하는 **UX Robustness Metrics**에 중점을 두었습니다. (UX Score = Mean Detection Rate - (Mean False Alarms * 20)).

| Model | Acc | F1 | Prec | Rec | Mean_Det(%) | Mean_FA | UX_Score |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Fold 2 | 0.895 | 0.821 | 0.801 | 0.843 | 83.900 | 1.500 | 78.900 |
| Fold 5 | 0.872 | 0.775 | 0.779 | 0.771 | 65.100 | 3.170 | 54.500 |
| Fold 1 | 0.858 | 0.765 | 0.726 | 0.808 | 56.200 | 1.580 | 51.000 |
| Fold 3 | 0.809 | 0.663 | 0.670 | 0.657 | 44.300 | 0.250 | 43.400 |
| Fold 4 | 0.752 | 0.544 | 0.573 | 0.518 | 0.000 | 0.000 | 0.000 |
| **K-Fold Average** | **0.837** | **0.714** | **0.710** | **0.719** | **49.900** | **1.300** | **45.600** |
| **Official WESAD w2.0** | **0.751** | **0.522** | **0.580** | **0.474** | **62.500** | **0.250** | **61.700** |

**결론:**
최종 배포용으로 채택된 Official 모델은 평균 K-Fold 대비 파편화된 정확도(Acc: 0.751)와 재현율이 다소 낮습니다. 그러나 피험자당 오알림 횟수(Mean_FA)를 1.3회에서 **0.25회**로 압도적으로 억제하여 최종 UX Score(61.700)에서 월등한 성능을 보입니다. 이는 잦은 오알림으로 인한 시스템 신뢰도 하락을 방지해야 하는 스트레스 감지 UX에 가장 부합하는 결과입니다.


## 2. Backend — FastAPI on AWS Seoul

100명 규모 베타 코호트를 대상으로 인증, 데이터 영속화, Watch–Phone 실시간 동기화, 옵트인 암호화 생체신호 보관, 감사 로그를 제공하는 서비스입니다. Firebase로 빠르게 만들 수도 있지만, 본 프로젝트는 시니어 수준의 백엔드 역량 자체를 산출물로 보여주기 위해 의도적으로 커스텀 백엔드 경로를 선택했습니다.

### 2.1 설계 원칙

1. **아키텍처로서의 프라이버시** — AWS, Supabase, 본 애플리케이션 중 어느 한쪽이 침해되더라도 사용자의 원시 생체신호는 복호화 불가능해야 한다. 사용자가 보유한 키 기반 E2E 암호화, 옵트인 업로드, 온디바이스 ML이 약속이 아닌 구조로 보장한다.
2. **필요한 것만 짓는다** — "쓸모 있을 수 있다"로 포장된 스코프 확장을 거절한다. 모든 컴포넌트는 PoC 스코프를 기준으로 자체 정당화를 통과해야 한다.
3. **운영은 1급 시민** — 로그·메트릭·트레이스·CI/CD를 애플리케이션 코드와 같은 시점에 설계한다. 관측 가능성은 v2의 과제가 아니다.
4. **표준 도구를 잘 쓴다** — Postgres, FastAPI, Terraform, GitHub Actions. 도구 선택의 화려함이 아니라 *어떻게 쓰는지*로 시니어 수준을 보인다.
5. **무엇이 아니라 왜를 문서화한다** — 결정의 근거를 보존하여 6개월 뒤의 자신·팀·검토자가 *왜*를 이해할 수 있게 한다.

#### 프라이버시 데이터 흐름 (옵트인 원시 생체신호)

![Biosignal pipeline — device → app → backend → storage with SSE-KMS encryption boundary and EventBridge purge job](docs/images/biosignal-pipeline.png)

- **블롭 바이트는 백엔드를 거치지 않습니다** — 폰이 presigned URL로 S3에 직접 PUT (`generate_presigned_url("put_object", ServerSideEncryption="aws:kms")`).
- **백엔드가 영속화하는 메타데이터**: `RawBiosignalUpload` 행은 `s3_object_key`, `signal_type`, `recorded_at`, `uploaded_at`, `expires_at`만 저장합니다. 요청 페이로드의 `byte_size`·`content_hash`는 검증용이며 DB에는 저장되지 않습니다.
- **암호화 (이중 방어)**: ① 클라이언트가 AES-256-GCM으로 블롭을 암호화 — 키는 Android Keystore에 보관되어 디바이스 밖으로 나가지 않습니다 ([BlobCipher.kt](frontend/android/app/src/main/kotlin/com/littlesignals/app/capture/BlobCipher.kt), [KeystoreBlobCipher.kt](frontend/android/app/src/main/kotlin/com/littlesignals/app/capture/KeystoreBlobCipher.kt)). ② 백엔드의 presigned URL이 `ServerSideEncryption=aws:kms`를 강제하므로 S3는 받은 사이퍼텍스트를 다시 SSE-KMS로 감쌉니다. 두 계층이 동시에 뚫리지 않는 한 원시 생체신호는 평문으로 복원되지 않습니다.
- **디바이스 종속 트레이드오프**: 마스터 키는 단일 디바이스 설치에 묶입니다. 앱을 재설치하거나 디바이스를 초기화하면 이전 S3 블롭은 영구적으로 복호화 불가가 되며, 이는 §2.1 약속의 의도된 결과입니다.
- **자동 만료 + 감사**: `recorded_at + 365일`. EventBridge Scheduler가 6시간 주기로 만료/동의 철회 행을 골라 S3 `delete_object`·DB row 삭제·`audit_log` 기록까지 한 번에 처리합니다 ([backend/app/jobs/purge_biosignals.py](backend/app/jobs/purge_biosignals.py)).

### 2.2 기술 스택

| 영역 | 선택 | 비고 |
| :--- | :--- | :--- |
| 언어/런타임 | Python 3.12 | ML 파이프라인과 동일 언어 |
| 웹 프레임워크 | FastAPI 0.136 | HTTP + WebSocket, 자동 OpenAPI |
| ASGI 서버 | uvicorn (`[standard]`) | 프로덕션은 다중 워커 |
| ORM / 드라이버 | SQLAlchemy 2.0 (asyncio) + asyncpg | 비동기 I/O |
| 마이그레이션 | Alembic | `backend/alembic/versions` |
| 검증 | Pydantic v2 + `pydantic-settings` | 환경변수 기반 설정 |
| 인증 | Supabase Auth (JWT 발급) + `python-jose` (검증) | 익명 우선 + Google OAuth |
| 알림 | Firebase Cloud Messaging (`firebase-admin`) | 백그라운드 푸시 |
| 객체 저장소 | AWS S3 (`boto3`) + presigned URL | 옵트인 암호화 블롭 |
| 로깅 | `structlog` → CloudWatch | 구조화 JSON, `trace_id` 포함 |
| 정적 검사 | `ruff`, `mypy --strict` | 라인 100, py312 타깃 |
| 테스트 | `pytest`, `pytest-asyncio`, `httpx`, `respx`, `moto` | 커버리지 = `sysmon` |
| HTTP 클라이언트 | `httpx` (+ `httpx-ws`) | 외부 호출/테스트 공용 |

### 2.3 인프라 (Terraform)

| 컴포넌트 | 역할 |
| :--- | :--- |
| VPC (퍼블릭/프라이빗 서브넷, IGW, NAT Gateway, EIP) | 3-AZ 네트워킹 (각 AZ에 퍼블릭/프라이빗 서브넷 1개씩), 단일 NAT GW로 비용 최적화, 프라이빗 서브넷에서 ECS·RDS 가동 |
| 보안 그룹 (`alb`, `ecs`, `rds`) | ALB→ECS→RDS 단방향 트래픽 경계 |
| Application Load Balancer | HTTPS(443) 단일 default forward → `backend` target group, HTTP(80)→HTTPS(443) 301 리다이렉트 (`backend/infra/alb.tf`). 경로 기반 라우팅은 ML 데모(`/api/v1/ml-demo/*` → `ml_demo` target group, `backend/infra/ml_demo.tf`)만 별도 listener rule로 분리 |
| ACM 인증서 + Route53 | `api-staging.friendlykr.com` TLS, DNS 검증 자동화, A 레코드 자동 등록 |
| ECS Fargate (desired_count = 1, 512 CPU / 1024 MiB) + ECS Cluster | FastAPI 애플리케이션 + WebSocket 호스팅 (오토스케일링 미설정 — 베타 코호트 100명 규모에 맞춘 단일 태스크) |
| ECS Task Definition (`backend`, `cron`, `ml-demo`) | 서비스 컨테이너 · EventBridge가 호출하는 일회성 잡 컨테이너 · `/api/v1/ml-demo/*` 데모 서비스 (`backend/infra/ml_demo.tf`) 분리 |
| IAM Role (`ecs_execution`, `ecs_task`, `scheduler`) | 시크릿 풀링 / 런타임 권한 / 스케줄러의 `RunTask` + `PassRole` |
| ECR (lifecycle policy 포함) | 컨테이너 이미지 레지스트리, 미사용 태그 자동 정리 |
| RDS Postgres 15 | 관계형 데이터(`stress_events`, `cycles`, `raw_biosignal_uploads` 등) |
| S3 `sync` (Seoul, SSE-KMS, versioning, abort-MPU 라이프사이클) | 옵트인 암호화 백업 블롭 (`/api/v1/sync`). 객체 만료 정책 없음 — 사용자가 `DELETE /api/v1/sync`로 초기화 |
| S3 `biosignals` (Seoul, SSE-KMS, versioning, lifecycle) | 옵트인 원시 생체신호 — 디바이스 Keystore의 AES-256-GCM으로 클라이언트 측 암호화된 사이퍼텍스트만 저장 (서버 복호화 불가), S3에서 SSE-KMS로 이중 보호 |
| EventBridge Scheduler + ECS RunTask | 6개 스케줄 (`backend/infra/scheduler.tf`): `purge_accounts` 매일 03:00 UTC · `purge_biosignals` 6시간 주기 (`cron(15 */6 * * ? *)`, 매시각 15분) · `weekly_reports` 토 17:00 UTC (= 일 02:00 KST, §2.8) · `prewarm_range_reports` 매일 18:00 UTC (= 03:00 KST, AI 리포트 캐시 사전 워밍) · `send_morning_tips` 매일 22:00 UTC (= 07:00 KST, 아침 푸시) · `send_sleep_nudges` 매일 02:00 UTC (= 11:00 KST, 수면 기록 리마인더) |
| AWS Bedrock (Anthropic Claude Haiku 4.5) | 패턴 팁 + 주간 리포트 생성, IAM에서 Haiku 4.5 인퍼런스 프로파일 + 그 하부 foundation-model에만 `InvokeModel` 허용 (§2.8) |
| SQS DLQ + CloudWatch Metric Alarm | 스케줄러 실패 격리 + DLQ depth 알람 |
| CloudWatch Log Groups (`backend`, `cron`, `otel_collector`, `ml_demo`) | structlog JSON 로그 수집 (`backend`·`cron`) + OTel 콜렉터 로그 + ML 데모 서비스 로그 |
| Secrets Manager (`supabase`, `firebase`, `sentry`) | Supabase 서비스 키 / Firebase Admin 자격증명 / Sentry DSN (`backend/infra/secrets.tf`) |

전체 정의는 [`backend/infra/`](backend/infra/) — `networking.tf`, `alb.tf`, `ecs.tf`, `ecr.tf`, `rds.tf`, `s3.tf`, `scheduler.tf`, `secrets.tf`.

### 2.4 데이터 모델 (요약)

`users`, `user_settings`, `stress_events`(append-only, 복합 PK `(id, detected_at)`), `cycles`, `sleep_logs`, `trigger_categories`, `raw_biosignal_uploads`(복합 PK `(id, recorded_at)`, 옵트인), `sync_blobs`, `websocket_connections`, `fcm_tokens`, `pattern_tips`(24h 캐시, `(user_id, pattern_key)` 유니크 — §2.8), `weekly_reports`(주간 잡 출력, `(user_id, week_start)` 유니크 — §2.8), `range_reports`(기간 선택 AI 리포트 캐시, `(user_id, period_start, period_end)` 유니크 — §2.8; `frm`/`to`는 API 쿼리스트링 이름), `audit_log`(append-only, `(action, occurred_at)` 인덱스). `stress_events`와 `raw_biosignal_uploads`는 TimescaleDB hypertable로 계획했으나 AWS RDS의 timescaledb 지원 종료로 plain Postgres 테이블로 유지합니다(`backend/app/models/stress_event.py:4-5`). 원시 생체신호 업로드는 사용자 동의가 있을 때만 수행되며, 클라이언트(Android Keystore 보관 AES-256-GCM 키)가 암호화한 ciphertext 상태로 S3에 저장됩니다. `stress_events.log_text` 같은 자유 텍스트 메모는 현재 Postgres에 저장되며, 원시 생체신호 암호화 경로와 별도로 취급됩니다.

### 2.5 API 요약

- `auth/*` — 익명 발급(`/anon`), Google OAuth 교환(`/google`), 이메일 로그인/가입(`/email/login`, `/email/signup`), OTP 비밀번호 재설정(`/password/forgot`, `/password/reset`), `/refresh`, `/logout`. 익명→Google 업그레이드는 `/auth/google` 내부에서 처리
- `me`, `account/{,restore}` — 프로필 조회/수정(GET·PATCH `/me`), 30일 유예 삭제(DELETE `/account`) 및 복구(POST `/account/restore`)
- `events/*` — 스트레스 이벤트 CRUD (list / `{event_id}` GET·PATCH·DELETE, POST)
- `cycles/*` — `/period-start`, `/current`, `/history`, `/{cycle_id}` PATCH
- `sleep-logs/*` — 수면 로그 CRUD + `/latest`
- `categories/*` — 트리거/카테고리 CRUD
- `dashboard/today` — 백엔드 aggregate route. 현재 Flutter Home은 이 단일 endpoint 대신 `events`, `cycles`, `consent`, `insights/morning-tip` 등 feature API를 fan-out 호출해 화면 상태를 조립
- `insights/*` — 백엔드 insight surface. 현재 Flutter 앱이 직접 호출하는 insight endpoint는 `/morning-tip` (24h 캐시, Bedrock — `send_morning_tips` 잡과 동일 캐시 공유)와 `/tips/{pattern_key}` (24h 캐시, Bedrock — §2.8)이며, 달력·phase chart·heatmap UI는 frontend가 `events + cycles` 데이터를 조합해 계산
- `reports/*` — `/range?frm&to` (기간 선택 AI 리포트 — 미생성 시 즉시 Bedrock 호출 후 캐시)가 현재 Flutter의 주요 wired report flow. `/weekly`는 주간 잡 결과 조회용 backend/API surface이며, `/drilldown`은 확장 surface로 유지
- `settings/*` — 사용자 환경설정 GET·PATCH
- `consent/*` — 동의 토글 + 감사 기록 GET·PATCH
- `sync/{upload,download}` — 옵트인 암호화 백업 (DELETE `/sync`는 백업 초기화)
- `sync/biosignals`, `sync/biosignals/batch` — 옵트인 원시 생체신호 metadata 등록 및 batch upload 준비
- `devices/fcm-token` — FCM 토큰 POST 등록 및 logout/account-switch cleanup용 DELETE unregister
- `ws/realtime` — Backend ↔ Flutter 실시간 fan-out 채널 (auth: 연결 직후 첫 JSON 메시지 `{type:"auth", token:"<jwt>"}`, 5초 타임아웃; Watch↔Phone 통신은 별도 Wear Data Layer 사용)

헬스체크: `GET /health → {"status":"ok","version":"0.8.0"}` (값은 `backend/app/config.py`의 `app_version` 기본값과 동일하며 배포마다 갱신). Swagger는 `/docs`, ReDoc은 `/redoc`, OpenAPI는 `/openapi.json`.

### 2.6 로컬 개발

사전 요구사항: Python 3.12 (pyenv), Poetry 2.x, Docker(Compose v2), `psql`.

```bash
cd backend
poetry install
docker compose up -d        # Postgres 15 + Adminer
make migrate                # alembic upgrade head
poetry run uvicorn app.main:app --reload
```

기본 접속: Postgres `localhost:5432` (`little_signals` / `dev_only_password` / `little_signals_dev`), Adminer `http://localhost:8080`. 5432 포트 충돌 시 호스트의 Postgres를 일시 중지하세요 (Homebrew: `brew services stop postgresql@15` / `postgresql@14` / `postgresql`, Linux systemd: `sudo systemctl stop postgresql`).

테스트:

```bash
poetry run pytest
make migrate-test
```

정적 검사:

```bash
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
```

### 2.7 스테이징 배포

기본 배포 경로는 GitHub Actions 워크플로 [`deploy-staging.yml`](.github/workflows/deploy-staging.yml) (OIDC → ECR buildx push → Alembic 일회성 태스크 → ECS 롤링 디플로이 → `make smoke-staging`). `master` 머지 또는 `workflow_dispatch`로 트리거됩니다.

아래 명령은 **최초 부트스트랩 또는 인프라/시크릿 변경 시의 수동 경로**입니다 (워크플로가 ECR 푸시 + Alembic + ECS 업데이트만 담당하므로, Terraform이나 시크릿 회전은 여전히 수동):

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/bootstrap-terraform-state.sh
cd infra
cp backend.hcl.example backend.hcl
AWS_PROFILE=little-signals-staging terraform init -backend-config=backend.hcl
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
cd ..
AWS_PROFILE=little-signals-staging make ecr-login
AWS_PROFILE=little-signals-staging make ecr-push IMAGE_TAG=0.8.0
cd infra
ECR_URL="$(AWS_PROFILE=little-signals-staging terraform output -raw ecr_repository_url)"
AWS_PROFILE=little-signals-staging terraform apply \
  -var-file=staging.tfvars \
  -var "container_image=$ECR_URL:0.8.0"
cd ..
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
make smoke-staging
```

스테이징 URL: `https://api-staging.friendlykr.com`.

### 2.8 Agentic AI — Bedrock + Claude Haiku 4.5

![Agentic AI architecture — Flow 1 (on-demand tip generation): Phone → FastAPI → RDS pattern_tips cache, miss → Bedrock InvokeModel → upsert → response. Flow 2 (scheduled weekly report): EventBridge cron(Sat 17:00 UTC) → ECS RunTask → aggregate stress + sleep + cycle → Bedrock JSON-schema prompt → upsert weekly_reports. Privacy & Safety panel — sent: display_name, category, phase, deltas, summary lines; never sent: UUID, email, free text, raw biosignals, FCM tokens. Tech stack: Flutter, FastAPI, ECS Fargate, RDS Postgres, Bedrock (Claude Haiku 4.5), EventBridge, AWS IAM.](docs/images/agenticai.png)

기존 통계 기반 패턴 탐지(§1의 Mamba 탐지와는 별개) 위에 LLM이 두 가지 형태로 사용자 경험을 보강합니다. 모든 호출은 백엔드 ECS에서 출발하며, 폰은 결과 텍스트만 받습니다.

**왜 별도 레이어인가**: §1의 Mamba는 *탐지*(300초 슬라이딩 버퍼의 마지막 60초 구간 1500 샘플을 Baseline/Stress 이진 분류 — `StressPipeline.kt:61-112`), 이 레이어는 *해석/요약*(이미 일어난 패턴을 자연어로 풀어주는 생성형). 두 모델은 입력·운영·비용 특성이 모두 달라 같은 코드 경로에 묶지 않았습니다.

| 표면 | 트리거 | 캐시/주기 | 출력 |
| :--- | :--- | :--- | :--- |
| 패턴 카드 팁 | `GET /api/v1/insights/tips/{pattern_key}` (폰 요청 시) | 24시간, `pattern_tips` 행 | 1-2 문장 한국어 팁 |
| 주간 리포트 | EventBridge `cron(0 17 ? * SAT *)` → ECS RunTask | 주 1회 (일 02:00 KST) | 헤드라인 + 마크다운 본문 + takeaways[] |

**기술 결정**

1. **AWS Bedrock + Anthropic Claude Haiku 4.5** — 한국어 톤·길이 제어, 의료적 진술 회피 등 안전성 요구사항을 만족하면서 가장 저렴한 frontier 모델. OpenAI/Google 대신 Bedrock을 택한 이유는 *데이터가 AWS 경계를 벗어나지 않는다*는 약속 한 줄이 §2.1의 프라이버시 원칙과 정합하기 때문입니다.
2. **`global.` 인퍼런스 프로파일** — `ap-northeast-2`에서 Haiku 4.5는 foundation-model ID 단독 호출 시 `ValidationException: on-demand throughput isn't supported`를 반환합니다. `global.anthropic.claude-haiku-4-5-20251001-v1:0` 프로파일이 가용 용량이 있는 리전으로 자동 라우팅합니다.
3. **24시간 DB 캐시** — 같은 패턴 카드가 하루 안에 여러 번 호출되어도 Bedrock 호출은 한 번뿐. `pattern_tips_user_key_unique`(`user_id`, `pattern_key`) 유니크 제약으로 중복 행을 차단.
4. **JSON 스키마 강제 + 결정적 폴백** — 주간 리포트 프롬프트는 `{headline, body_md, takeaways[]}` JSON만 출력하도록 지시. 모델이 JSON을 깨뜨리면 `_fallback_summary()`가 통계 기반 결정적 요약을 대신 저장하므로 주간 잡이 *항상* 행을 쓴다는 불변식을 유지.
5. **kill switch** — `AI_FEATURES_ENABLED` 환경변수가 `false`면 두 엔드포인트가 모두 404. 모델 액세스/한도 문제 시 코드 배포 없이 차단할 수 있습니다.

**Bedrock에 보내는 데이터 vs 보내지 않는 데이터**

| 보내는 것 | 절대 보내지 않는 것 |
| :--- | :--- |
| `display_name`(한국어 닉네임만) | 사용자 UUID·이메일 |
| 카테고리 이름 (예: "업무") | 자유 텍스트 노트(`note`, `log_text`) |
| 사이클 단계 (예: "황체기") | 원시 생체신호 (HR/EDA/PPG) |
| 집계 수치·델타 (예: "+28%") | FCM 토큰·기기 식별자 |
| 익명 요약 라인 (예: "월 09:00 · 강도 3") | 이메일·전화번호·비밀번호 |

프롬프트 빌더([`backend/app/services/ai/prompts.py`](backend/app/services/ai/prompts.py))가 이 경계를 강제합니다. 생성기 코드는 집계만 받으므로 위 표 오른쪽 칼럼은 구조적으로 외부로 나갈 수 없습니다.

**주간 잡 흐름**

```
EventBridge Scheduler  ──Sat 17:00 UTC──►  ECS RunTask (cron task definition)
(weekly_reports)                                │
                                                ├─ 지난 Mon-Sun 윈도우 내 stress_event를
                                                │  남긴 user_id 집합 조회
                                                │
                                                ├─ for each user:
                                                │    ① stress + sleep + cycle 집계
                                                │    ② 한국어 JSON 스키마 프롬프트 생성
                                                │    ③ Bedrock InvokeModel (Haiku 4.5)
                                                │    ④ JSON 파싱 (실패 시 폴백)
                                                │    ⑤ weekly_reports 행 UPSERT
                                                │       (user_id, week_start) 유니크
                                                │
                                                └─ db.commit()

백엔드/API surface  ──GET /reports/weekly──►  API ──최신 행 SELECT
```

현재 Flutter 앱의 주요 AI 리포트 화면은 사용자가 선택한 기간을 기준으로 `GET /reports/range?frm&to`를 호출합니다. `/reports/weekly`는 scheduled weekly report 결과를 조회하는 backend/API surface이며, 현재 앱 내 주 navigation flow의 기본 report 화면은 아닙니다.

**관련 파일**

- 어댑터: [`backend/app/services/ai/bedrock_client.py`](backend/app/services/ai/bedrock_client.py) (boto3를 asyncio 익스큐터로 감싼 얇은 래퍼)
- 프롬프트: [`backend/app/services/ai/prompts.py`](backend/app/services/ai/prompts.py) (한국어 system + user 페어)
- 팁 생성기: [`backend/app/services/ai/tip_generator.py`](backend/app/services/ai/tip_generator.py)
- 리포트 생성기: [`backend/app/services/ai/weekly_report.py`](backend/app/services/ai/weekly_report.py)
- 잡 / 스크립트: [`backend/app/jobs/weekly_reports_job.py`](backend/app/jobs/weekly_reports_job.py), [`backend/scripts/run_weekly_reports.py`](backend/scripts/run_weekly_reports.py)
- 인프라: [`backend/infra/scheduler.tf`](backend/infra/scheduler.tf) (`aws_scheduler_schedule.weekly_reports`), [`backend/infra/ecs.tf`](backend/infra/ecs.tf) (`aws_iam_role_policy.ecs_task_bedrock` — `bedrock:InvokeModel`을 Haiku 4.5에만 한정)

---

## 3. Wear OS — Galaxy Watch 8 센서 캡처

[`watch/sensor-capture/`](watch/sensor-capture/)는 Galaxy Watch 8에서 4개 채널의 원시 센서 데이터를 수집하는 Wear OS 앱입니다. 현재 설계는 두 가지 진입점을 함께 제공합니다.

1. **Phone-driven streaming mode** — Flutter Watch/Biosignal 화면에서 사용자가 opt-in capture를 시작하면 phone이 Wear Data Layer로 `/biosignals/start` / `/biosignals/stop` control message를 보내고, watch는 `RemoteCaptureService` foreground service로 채널을 열어 `/biosignals/samples` batch를 phone에 전달합니다. Phone native layer가 ONNX inference, stress event creation, encrypted window upload를 담당합니다.
2. **Standalone 10-minute ZIP export mode** — ML 검증이나 센서 품질 확인이 필요할 때 watch에서 직접 10분 capture를 실행하고 CSV/metadata ZIP을 app-private storage에 저장해 `adb run-as`로 추출합니다.

두 mode는 `ChannelRecorder`와 Samsung Health Sensor SDK glue를 공유하지만, 운영 목적은 다릅니다. Streaming mode는 phone app pipeline과 연결되고, ZIP export mode는 offline/model verification 산출물 생성에 사용됩니다.

#### Standalone ZIP 캡처 세션 상태 머신

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Connecting: tap Start
    Connecting --> Capturing: first sensor sample
    Capturing --> Capturing: tick (remainingSec)
    Capturing --> Done: 10 min elapsed → ZIP written
    Connecting --> Error: SDK / permission failure
    Capturing --> Error: capture exception
    Done --> Idle: tap Reset
    Error --> Idle: tap Reset
```

아래 상태 전이는 standalone ZIP export 화면인 [`CaptureActivity.kt`의 `Status` sealed class](watch/sensor-capture/app/src/main/kotlin/com/littlesignals/capture/CaptureActivity.kt)에 정의되어 있고, `capture { remaining -> ... }` 람다가 매 초 `Capturing(remainingSec)` 상태를 갱신합니다. 성공 시 ZIP 경로를 반환하며 `Done`으로 전이하고, 임의의 throwable은 `Error(message)`로 잡힙니다.

### 3.1 캡처 채널

| 채널 | Samsung 트래커 | 관측 샘플레이트 | 모델 용도 |
|---|---|---|---|
| Heart rate + IBI | `HEART_RATE_CONTINUOUS` | ~1 Hz (event-driven) | HRV — 스트레스 모델의 근간 |
| PPG green | `PPG_GREEN` | ~25 Hz | 원시 광학 신호, 모델 입력 |
| EDA | `EDA_CONTINUOUS` | ~1 Hz | 피부 전도도, 두 번째 핵심 신호 |
| Accelerometer | `ACCELEROMETER_CONTINUOUS` | ~25 Hz | 모션 아티팩트 필터 / 활동 게이팅 |

피부 온도는 의도적으로 제외되었습니다. 저빈도 사이클 컨텍스트일 뿐 스트레스 모델 입력이 아닙니다.

### 3.2 SDK 검증 결과 (2026-05-04)

Samsung Health Sensor SDK 1.4.1 (`samsung-health-sensor-api-1.4.1.aar`)을 직접 검수하여, `HealthTrackerType` 열거형으로 다음이 노출됨을 확인했습니다.

```kotlin
ValueKey.HeartRateSet.HEART_RATE          // BPM
ValueKey.HeartRateSet.IBI_LIST            // HRV 입력
ValueKey.PpgGreenSet.PPG_GREEN            // 원시 PPG 샘플
ValueKey.EdaSet.SKIN_CONDUCTANCE          // EDA 값
ValueKey.AccelerometerSet.ACCELEROMETER_X // x/y/z 동일
```

v1 모델이 필요로 하는 4개 채널(연속 PPG, 심박+IBI, 연속 EDA, 연속 가속도)이 모두 연속 이벤트 스트림으로 제공됨을 실제 워치에서 검증 완료했습니다. 현재 `ChannelRecorder.kt`(`watch/sensor-capture/app/src/main/kotlin/com/littlesignals/capture/ChannelRecorder.kt`)에서 실제로 사용하는 상수는 `ValueKey.HeartRateSet.{HEART_RATE, HEART_RATE_STATUS, IBI_LIST}`, `ValueKey.PpgGreenSet.{PPG_GREEN, STATUS}`, `ValueKey.EdaSet.SKIN_CONDUCTANCE`, `ValueKey.AccelerometerSet.{ACCELEROMETER_X, ACCELEROMETER_Y, ACCELEROMETER_Z}` 입니다. SDK 마이너 버전 업그레이드 시 상수명이 바뀔 수 있으므로(예: `SKIN_CONDUCTANCE`가 과거 `RESISTANCE`로 노출됐던 시기 존재), 채널 계약(BPM/IBI 리스트/상태 코드/x·y·z)은 안정적임을 전제로 IDE 자동완성으로 매칭되는 상수를 다시 선택해 반영합니다.

### 3.3 출력 레이아웃

Standalone 10분 캡처가 성공하면 워치의 다음 경로에 결과가 생성됩니다.

```
/data/data/com.littlesignals.capture/files/captures/
├── 2026-05-06T15-30-00Z/
│   ├── heart_rate.csv          timestamp_ms, hr_bpm, ibi_ms, hr_status
│   ├── ppg_green.csv           timestamp_ms, ppg_green, status
│   ├── eda.csv                 timestamp_ms, skin_conductance, status   # μS
│   ├── accel.csv               timestamp_ms, x, y, z
│   └── metadata.json           start/end ts, watch model, observed sample rates
└── 2026-05-06T15-30-00Z.zip    # ML 팀에 전달하는 단일 산출물
```

`timestamp_ms`는 SDK의 `DataPoint.timestamp` (벽시계 UTC ms). Phone-driven streaming mode는 같은 per-sample tuple을 CSV/ZIP으로 저장하지 않고 `SampleBatch` payload로 phone에 전달합니다.

### 3.4 빌드와 실행

요구사항: Android Studio (Iguana / Koala 이상), 개발자 모드가 활성화되어 `adb devices`에 노출되는 Galaxy Watch 8, 저장소에 포함된 `libs/samsung-health-sensor-api-1.4.1.aar`.

```bash
cd watch/sensor-capture
gradle wrapper --gradle-version 8.11.1
./gradlew :app:assembleDebug
./gradlew :app:installDebug
adb shell am start -n com.littlesignals.capture/.CaptureActivity
```

워치를 80% 이상 충전 후, **첫 2분은 정자세**, 이후 8분은 일상 활동(보행, 타이핑, 기립·착석 등)으로 진행하면 휴식·동작 구간 모두 포함된 데이터가 만들어집니다.

### 3.5 데이터 추출

```bash
SESSION="2026-05-06T15-30-00Z"
adb exec-out run-as com.littlesignals.capture cat \
  files/captures/${SESSION}.zip > ${SESSION}.zip

unzip -l ${SESSION}.zip
unzip -p ${SESSION}.zip metadata.json | jq .
unzip -p ${SESSION}.zip ppg_green.csv | wc -l   # 25Hz × 600s + 헤더 1행 = 15,001
```

루팅되지 않은 워치에서는 `adb pull /data/data/...`가 실패하므로, 디버그 빌드의 `run-as ... cat` 패턴이 표준입니다. 행이 0이거나 값이 전부 0/-1이면 권한 거부 또는 착용 불량을 의심하고 `adb logcat | grep -i capture`로 확인 후 재시도합니다.

자세한 설치·검증·재사용 가이드는 [`watch/sensor-capture/README.md`](watch/sensor-capture/README.md).

---

## 4. Frontend — Flutter Android App

### 4.1 Frontend 개요

`frontend/`는 Luma의 Flutter 기반 Android 모바일 애플리케이션입니다. 사용자가 직접 만나는 presentation layer로서 스트레스 기록, 생리 주기 맥락 기반 인사이트, 수면 데이터 화면, 선택 기간 AI 리포트, 알림 등록, 원시 생체신호 캡처 UX를 담당합니다.

앱은 staging FastAPI backend와 REST API로 통신하며, 화면 상태는 Provider 기반으로 관리됩니다. 사용자는 Auth 화면에서 진입한 뒤 Home dashboard를 중심으로 스트레스 기록, My Cycle, Sleep Data, Insight, Profile, Watch/Biosignal Capture 화면을 오갑니다. UI copy는 한국어 사용 맥락에 맞춰 부드럽고 부담이 적은 tone을 유지합니다.

### 4.2 설계 목표

Frontend는 사용자의 기록 부담을 낮추고, 민감한 건강 맥락을 조심스럽게 다루는 것을 목표로 설계되었습니다.

1. **빠른 stress logging UX**
   사용자는 Home 또는 기록 목록에서 스트레스 강도, 요인, 메모를 빠르게 남기고 수정할 수 있습니다. 저장된 기록은 provider refresh를 통해 Home, Insight, Report 화면에 반영됩니다.

2. **Cycle-aware insight visualization**
   스트레스 기록은 생리 주기 정보와 함께 해석됩니다. Home의 cycle card, My Cycle auto-save, Insight calendar, report UI는 사용자가 주기 단계와 스트레스 패턴을 함께 볼 수 있도록 구성되어 있습니다.

3. **Staging backend 기반 실사용 flow**
   Auth, profile, events, cycles, categories, consent, sleep logs, selected-period AI reports, device token registration, biosignal sync metadata가 staging API client layer를 통해 호출됩니다.

4. **Biosignal capture/upload UX**
   Watch/Biosignal 화면은 raw biosignal consent, capture source 선택, duration 선택, live status, upload window count, summary screen을 제공합니다. Flutter UI는 Android native capture layer와 MethodChannel/EventChannel로 연결됩니다.

5. **Korean UI copy 중심의 interaction**
   nickname, trigger, cycle, sleep, notification, privacy copy는 한국어 서비스 tone에 맞춰 정리되어 있으며, 사용자-facing label과 backend/raw data를 분리하는 formatter를 사용합니다.

### 4.3 기술 스택

| 영역 | 기술 |
| :--- | :--- |
| App framework | Flutter / Dart |
| State management | Provider |
| Backend communication | REST API client layer |
| Auth frontend flow | Anonymous auth, Google Sign-In frontend flow |
| Push infrastructure | Firebase Messaging / FCM device token registration + unregister |
| Native bridge | MethodChannel / EventChannel |
| Android native integration | Kotlin, Android foreground service |
| Wear communication boundary | Wear Data Layer |
| Android package | `com.littlesignals.app` |
| Testing | Flutter tests, regression smoke tests, Android/Kotlin unit tests |

사용자-facing branding은 `Luma`입니다. Android package와 일부 runtime env key는 현재 빌드 및 배포 호환성을 위해 `com.littlesignals.app`, `LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID` 이름을 사용합니다.

### 4.4 구현된 주요 기능

현재 frontend에는 다음 사용자 흐름과 integration이 구현되어 있습니다.

* Auth landing
* Anonymous auth
* Google Sign-In frontend request flow
* Home dashboard
* Stress log create/edit
* Trigger/category management
* Cycle current/history/create/update flow
* My Cycle auto-save UX
* Sleep log display states
* Insight calendar / report UI
* AI selected-period report card/detail UI
* Profile / nickname editing
* Notification permission handling
* FCM device token registration and logout/account-switch unregister
* Watch / biosignal capture UI
* Raw biosignal consent toggle
* Capture source picker
* Capture status / summary screen
* Session cleanup/provider reset
* Korean UI copy polish
* Regression smoke tests

### 4.5 Architecture 요약

Frontend는 shared core layer, feature layer, screen layer, native capture layer로 나뉩니다.

* `lib/core/`는 app-wide foundation입니다. API base URL, shared `ApiClient`, secure token storage, theme, spacing, shared widgets, Korean UI formatter를 포함합니다.
* `lib/features/`는 domain별 provider, model, service, API adapter를 포함합니다. Auth, Events, Cycles, Sleep, Triggers, Insight, Consent, Notifications, Privacy, Biosignals가 이 계층에 있습니다.
* `lib/screens/`는 실제 화면 composition을 담당합니다. Home, Insight, My/Profile, Stress Log, My Cycle, Sleep Data, Watch/Biosignal Capture 화면이 Provider state를 소비합니다.
* Provider는 화면 상태와 사용자 action을 조율합니다. 예를 들어 `EventsProvider`는 stress event create/edit flow를 관리하고, `CycleProvider`는 cycle save/update와 My Cycle auto-save를 담당하며, `InsightProvider`는 event/cycle data와 selected-period report를 조합합니다.
* `features/*/data` API layer는 backend endpoint와 JSON mapping을 캡슐화합니다. UI는 HTTP path나 backend response shape를 직접 다루지 않고 provider를 통해 domain state를 읽습니다.
* Native capture/inference layer는 `features/biosignals/`의 Flutter bridge와 두 개의 Android Kotlin 패키지로 구성됩니다 — `android/app/src/main/kotlin/com/littlesignals/app/capture/` (foreground service, Wear Data Layer messaging, sample buffering, WindowUploader가 만드는 presigned S3 PUT upload)와 `android/app/src/main/kotlin/com/littlesignals/app/inference/` (`StressPipeline`, `StreamingInferenceCoordinator`, `OnnxInferenceEngine`, `CapturePreprocessor`, `DetectionResult` — §1.4의 결정 엔진(신뢰도 ≥60%, MAR 0.10, 120s gap, 300s cooldown)이 실제로 동작하는 위치). Flutter는 capture command·status stream·detection stream만 다룹니다.

### 4.6 사용자 흐름

```mermaid
flowchart TD
    A["Auth Landing"] --> B{"Login method"}
    B --> C["Anonymous Auth"]
    B --> D["Google Sign-In frontend flow"]
    C --> E["Home Dashboard"]
    D --> E

    E --> F["Stress Log"]
    E --> G["My Cycle"]
    E --> H["Sleep Data"]
    E --> I["Insight / Report"]
    E --> J["Profile"]
    J --> K["Watch / Biosignal Capture"]
    H --> K

    F --> F1["Stress score"]
    F --> F2["Trigger/category"]
    F --> F3["Memo"]
    F --> F4["Create or edit event"]

    G --> G1["Select period start/end"]
    G1 --> G2["Auto-save cycle"]
    G2 --> G3["Refresh Home and Insight"]

    H --> H1["Empty state"]
    H --> H2["Latest/history sleep state"]

    I --> I1["Insight calendar"]
    I --> I2["Cycle x stress report"]
    I --> I3["AI selected-period report card/detail"]

    K --> K1["Raw biosignal consent"]
    K1 --> K2["Source picker"]
    K2 --> K3["Duration picker"]
    K3 --> K4["Native capture session"]
    K4 --> K5["Capture summary"]
```

### 4.7 Frontend Data Flow

```mermaid
flowchart LR
    UI["Flutter UI<br/>screens"] --> Provider["Provider state<br/>Auth, Events, Cycle, Sleep, Insight, Triggers"]
    Provider --> DataAPI["Feature data API<br/>features/*/data"]
    DataAPI --> ApiClient["Shared ApiClient<br/>token refresh, request id, JSON mapping"]
    ApiClient --> Backend["FastAPI staging backend"]
    Backend --> ApiClient
    ApiClient --> DataAPI
    DataAPI --> Provider
    Provider --> UI

    UI --> CaptureController["BiosignalCaptureController"]
    CaptureController --> Channels["MethodChannel / EventChannel"]
    Channels --> ForegroundService["Android foreground service"]
    ForegroundService --> Source{"Capture source"}
    Source --> Wear["Wear Data Layer"]
    Source --> Synthetic["SyntheticSampleSource"]
    Wear --> Receiver["WatchSampleReceiver"]
    Receiver --> WatchBuffer["WatchSourceController"]
    Synthetic --> Uploader["WindowUploader"]
    WatchBuffer --> Uploader
    Uploader --> Batch["POST /api/v1/sync/biosignals/batch"]
    Batch --> Backend
    Backend --> Presigned["Presigned S3 PUT URL"]
    Presigned --> S3["S3 encrypted biosignal object"]
```

### 4.8 Backend Integration

Frontend는 staging backend와 다음 API 흐름을 사용합니다. 이 표는 현재 Flutter/Android frontend가 실제로 호출하는 wired API를 기준으로 정리합니다.

| 기능 | API |
| :--- | :--- |
| Auth | `POST /api/v1/auth/anon`, `POST /api/v1/auth/google`, `POST /api/v1/auth/email/login`, `POST /api/v1/auth/email/signup`, `POST /api/v1/auth/refresh`, `POST /api/v1/auth/logout`, `POST /api/v1/auth/password/forgot`, `POST /api/v1/auth/password/reset` |
| User profile | `GET /api/v1/me`, `PATCH /api/v1/me`, `DELETE /api/v1/account`, `POST /api/v1/account/restore` |
| Stress events | `GET /api/v1/events`, `POST /api/v1/events`, `PATCH /api/v1/events/{id}`, `DELETE /api/v1/events/{id}` |
| Cycle | `GET /api/v1/cycles/current`, `GET /api/v1/cycles/history`, `POST /api/v1/cycles/period-start`, `PATCH /api/v1/cycles/{id}` |
| Trigger/category | `GET /api/v1/categories`, `POST /api/v1/categories`, `PATCH /api/v1/categories/{id}`, `DELETE /api/v1/categories/{id}` |
| Home dashboard | Feature API fan-out: `GET /api/v1/events`, `GET /api/v1/cycles/current`, `GET /api/v1/consent`, `GET /api/v1/insights/morning-tip` |
| Insight local aggregation | Frontend가 `events + cycles` 데이터를 조합해 calendar, Cycle × Stress, phase distribution/average, heatmap-style UI를 계산합니다. 현재 app flow에서는 `/api/v1/insights/calendar`, `/trends`, `/phase-averages`, `/heatmap`, `/patterns`를 호출하지 않습니다 |
| AI insights | `GET /api/v1/insights/morning-tip`, `GET /api/v1/insights/tips/{pattern_key}` |
| Selected-period AI report | `GET /api/v1/reports/range?frm={YYYY-MM-DD}&to={YYYY-MM-DD}` |
| Consent | `GET /api/v1/consent`, `PATCH /api/v1/consent` |
| Settings | `GET /api/v1/settings`, `PATCH /api/v1/settings` |
| Sleep logs | `GET /api/v1/sleep-logs/latest`, `GET /api/v1/sleep-logs`, `POST /api/v1/sleep-logs`, `PATCH /api/v1/sleep-logs/{id}`, `DELETE /api/v1/sleep-logs/{id}` |
| Device token | `POST /api/v1/devices/fcm-token`, `DELETE /api/v1/devices/fcm-token` |
| Realtime fan-out | `WSS /ws/realtime` (auth: 첫 JSON 메시지 `{type:"auth", token:"<jwt>"}`, 5초 타임아웃) |
| Privacy/sync backup | `GET /api/v1/sync/download`, `POST /api/v1/sync/upload`, `DELETE /api/v1/sync` |
| Raw biosignal sync | `POST /api/v1/sync/biosignals/batch`, presigned S3 `PUT` upload flow |

Stress, cycle, sleep, trigger, profile, consent, report data는 feature별 API adapter에서 domain model로 변환된 뒤 Provider를 통해 화면에 전달됩니다. Home dashboard는 현재 `/api/v1/dashboard/today` 단일 호출이 아니라 feature API fan-out으로 조립됩니다. Weekly/drilldown report endpoint는 backend/API surface로 존재할 수 있으나, 현재 Flutter의 주요 wired report flow는 selected-period `/api/v1/reports/range`입니다. Raw biosignal upload는 Android native `WindowUploader`가 batch metadata를 backend에 등록하고, backend가 반환한 presigned S3 PUT URL로 채널별 payload를 업로드하는 구조입니다.

### 4.9 Native Capture Integration

Watch/Biosignal capture 화면은 phone-side raw biosignal capture/upload infrastructure와 연결되어 있습니다.

* Flutter `BiosignalCaptureService`는 `MethodChannel('littlesignals/capture')`로 `start`, `stop`, `isWatchConnected` command를 호출합니다.
* Flutter `BiosignalCaptureService`는 `EventChannel('littlesignals/capture/status')`로 capture state, elapsed seconds, uploaded window count, error state를 수신합니다.
* Android `CaptureChannels`는 Flutter method/event channel을 등록하고, `BiosignalCaptureService` foreground service를 시작합니다.
* Android foreground service는 timed/manual capture session을 실행하고 notification으로 capture 상태를 유지합니다.
* `WearMessageClient`는 Wear Data Layer reachable node/capability를 확인하고 `/biosignals/start`, `/biosignals/stop` message를 보냅니다.
* `WatchSampleReceiver`는 `/biosignals/samples`, `/biosignals/end` message를 수신합니다.
* `WatchSourceController`는 HR, PPG, EDA, accelerometer sample batch를 buffer에 모읍니다.
* `SyntheticSampleSource`는 capture/upload plumbing을 확인할 수 있는 synthetic sample source를 제공합니다.
* `WindowUploader`는 1분 단위 window를 만들고 `hrv`, `ppg`, `eda`, `accel` payload를 Android Keystore 기반 AES-GCM으로 암호화한 뒤 backend batch registration 및 presigned S3 PUT upload flow로 보냅니다.
* Capture session이 끝나면 Flutter는 elapsed time, uploaded window count, estimated data size를 summary screen에 표시합니다.

이 섹션의 범위는 wearable-oriented raw biosignal capture/upload infrastructure이며, app의 stress/cycle/sleep 기록 UX와 병렬로 동작하는 capture/upload 경로를 다룹니다.

### 4.10 Notification Flow

앱은 Firebase Messaging을 사용해 알림 권한과 device token registration/unregister를 처리합니다. 현재 범위는 push notification infrastructure와 stress event notification entry path이며, production 수준의 전체 알림 제품 로직(그룹핑, 재시도 정책, preference/cooldown UX 전체)은 별도 확장 범위입니다.

* Authenticated session load 시 `NotificationService.requestPermissionAndRegister()`가 호출됩니다.
* Firebase Messaging permission prompt 결과를 확인한 뒤 FCM token을 가져옵니다.
* token이 존재하면 `NotificationsApi.registerDeviceToken()`이 `/api/v1/devices/fcm-token`으로 `token`, `platform: android`를 전송합니다.
* Logout/account switch cleanup 시 현재 FCM token unregister를 먼저 시도해 stale token이 남지 않도록 정리합니다. Unregister 실패는 logout 자체를 막지 않습니다.
* Notification copy는 OS locale에 맞춰 Korean/English text를 제공하며, 권한 안내와 fallback notification 문구를 분리해 관리합니다.

### 4.11 Frontend 실행과 테스트

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run
```

Google OAuth web client ID를 명시적으로 지정할 때는 다음 runtime define을 사용합니다.

```bash
flutter run --dart-define=LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

사용자-facing branding은 `Luma`이며, Android package와 Google OAuth runtime define은 `com.littlesignals.app`, `LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID` 이름을 사용합니다.

Regression smoke tests는 auth navigation, anonymous auth, main tabs, Home dashboard, stress log create/edit, trigger management, cycle auto-save, sleep display states, notification copy, nickname/session cleanup, provider reset 흐름을 검증합니다. Android/Kotlin unit tests는 `SyntheticSampleSource`, `WindowUploader`, `WearMessageClient`, `WatchSourceController`의 capture layer behavior를 검증합니다.


## 5. 아키텍처 전체 흐름 (요약)

```mermaid
flowchart TD
    subgraph Watch["Galaxy Watch 8 — Wear OS, Kotlin"]
        SDK["Samsung Health Sensor SDK 1.4.1<br/>PPG_GREEN · HEART_RATE_CONTINUOUS<br/>EDA_CONTINUOUS · ACCELEROMETER_CONTINUOUS"]
        StreamRec["StreamingRecorder × 4<br/>(채널별 DataPoint 라우팅)"]
        Consumer["PhoneSenderConsumer<br/>1Hz 배치 + /biosignals/samples"]
        SDK --> StreamRec --> Consumer
    end

    subgraph Phone["Phone — Android-native Kotlin + Flutter UI"]
        Receiver["WatchSampleReceiver<br/>/biosignals/samples · /biosignals/end"]
        Buffer["StreamingPreprocessor<br/>300s 슬라이딩 윈도 · 25Hz 재샘플링<br/>Butterworth + SavGol"]
        Mamba["StressPipeline (Mamba 추론)<br/>onnxruntime-android · 9-channel 2-class<br/>60s 케이던스"]
        Decision["Decision Engine<br/>모션 게이트 · 쿨다운 · 감지 판단"]
        FlutterUI["Flutter UI<br/>최신 감지 카드 · 기록 진입"]
        REST["REST · /api/v1/*"]
        WSS["WSS · /ws/realtime"]
        FCMc["FCM consumer"]
        Receiver --> Buffer --> Mamba --> Decision
        Decision --> FlutterUI
        Decision --> REST
        FlutterUI -- "subscribe" --> WSS
        FCMc --> FlutterUI
    end

    subgraph AWS["AWS Seoul (ap-northeast-2)"]
        ALB["Application Load Balancer"]
        ECS["ECS Fargate<br/>FastAPI · structlog · OTel"]
        RDS[("RDS Postgres 15")]
        S3[("S3<br/>KMS · 옵트인 암호화 블롭")]
        EB["EventBridge Scheduler<br/>→ ECS RunTask (purge)"]
        Ops["Secrets Manager · CloudWatch · SQS DLQ"]
        ALB --> ECS
        ECS --> RDS
        ECS --> S3
        EB --> ECS
        ECS -.-> Ops
    end

    Firebase[("Firebase Cloud Messaging")]

    Consumer -- "Wear Data Layer" --> Receiver
    REST --> ALB
    WSS --> ALB
    ECS -- push --> Firebase
    Firebase --> FCMc
```

---

## 6. 문서

내부 검토자(평가위원·심사자·신규 합류자)는 다음 순서로 읽으면 됩니다.

| # | 문서 | 다루는 범위 |
| :---: | :--- | :--- |
| 1 | 본 README §2.1–§2.5 | 백엔드 설계 원칙·기술 스택·인프라·데이터 모델·API 요약 |
| 2 | [`backend/README.md`](backend/README.md) | 모듈별(라우터/서비스/스키마/관측성) 상세 |
| 3 | [`backend/infra/README.md`](backend/infra/README.md) | Terraform 모듈 구성, 변수, 배포 절차 |
| 4 | [`backend/docs/sprint-7-deploy-runbook.md`](backend/docs/sprint-7-deploy-runbook.md) | EventBridge + ECS RunTask 이관, `audit_log` 도입 런북 |
| 5 | [`watch/sensor-capture/README.md`](watch/sensor-capture/README.md) | Wear OS 4채널 캡처 도구 사용·검증 |
| 6 | [`CONTRIBUTING.md`](CONTRIBUTING.md) | 브랜치 규칙·PR 워크플로우·보안 영역 추가 승인 |

내부 전체 스펙(공개 저장소에 포함하지 않는 부분)이 필요한 경우 §6 팀 연락처로 요청해 주세요.

---

## 7. 팀 소개

<table>
  <tr>
    <td align="center" width="160">
      <a href="https://github.com/nukktae">
        <img src="https://github.com/nukktae.png" width="96" height="96" alt="Anu Bilegdemberel"/><br/>
        <sub><b>아노</b></sub>
      </a><br/>
      <sub><b>팀장</b> · Backend / Infra / Wear OS / AI 통합</sub><br/>
      <sub><a href="mailto:anu.bnda@gmail.com">anu.bnda@gmail.com</a></sub>
    </td>
    <td align="center" width="160">
      <a href="https://github.com/joonseojj">
        <img src="https://github.com/joonseojj.png" width="96" height="96" alt="윤준서"/><br/>
        <sub><b>윤준서</b></sub>
        </a><br/>
        <sub>Data / AI</sub><br/>
        <sub><a href="mailto:joonseojj@gmail.com">joonseojj@gmail.com</a></sub>
      </a><br/> 
    </td>
    <td align="center" width="160">
      <a href="https://github.com/pnpn777">
        <img src="https://github.com/pnpn777.png" width="96" height="96" alt="pnpn777"/><br/>
        <sub><b>예르잔 울판</b></sub>
      </a><br/>
      <sub>Frontend / UX /UI Design</sub>
       <sub><a href="mailto:yerzhanulpan@kookmin.ac.kr">yerzhanulpan@kookmin.ac.kr</a></sub>
    </td>
    <td align="center" width="160">
      <a href="https://github.com/seennothing">
        <img src="https://github.com/seennothing.png" width="96" height="96" alt="초라핀스카 베로니카"/><br/>
        <sub><b>초라핀스카 베로니카</b></sub>
      </a><br/>
      <sub>Data / AI Engineer</sub><br/>
      <sub><a href="mailto:czorapinska@kookmin.ac.kr">czorapinska@kookmin.ac.kr</a></sub>
    </td>
  </tr>
</table>

| 이름 | 역할 | 담당 영역 | 연락처 |
| :--- | :--- | :--- | :--- |
| 아노 (nukktae) | 팀장 · Backend Engineer | • Backend 아키텍처 설계·구현 (FastAPI 0.136 + asyncio, SQLAlchemy 2.0/asyncpg, Alembic, Pydantic v2, Supabase JWT 인증, FCM 푸시, structlog/OTel 관측성, 9개 스프린트 운영)<br>• AWS 클라우드 인프라(ECS Fargate, RDS Postgres 15, ALB, S3, EventBridge, Terraform)<br>• Agentic AI 파이프라인 설계·운영<br>• Wear OS — Galaxy Watch 8 센서 캡처 도구(Kotlin, Samsung Health Sensor SDK 1.4.1) 구현 및 PPG/HRV/EDA/가속도 4채널 검증<br>• UX 설계 및 사용자 흐름<br>• Frontend ↔ Backend ↔ ONNX 온디바이스 추론 간 종단 연동(REST/WebSocket/FCM, 모델 직렬화·배포 파이프라인)<br>• 랜딩 페이지 디자인 및 개발<br>• Blender 기반 3D 렌더링 | <anu.bnda@gmail.com> · [LinkedIn](https://www.linkedin.com/in/anu-bilegdemberel-445366318/) |
| 예르잔 울판 (pnpn777) | Frontend / UX-UI Engineer | • Flutter frontend architecture <br>•  Korean UX copy 및 interaction flow 설계<br>• UX research 및 여성 스트레스·생리 주기 기반 사용자 흐름 설계<br>• MVP 범위 정의 및 feature prioritization<br>• Home / Insight / Profile UX 및 visual hierarchy 설계<br>• Figma 기반 mobile UI design system 및 component flow 정리 | <yerzhanulpan@kookmin.ac.kr> |
| 윤준서 (joonseojj) | Data / AI Engineer | • WESAD 전처리 파이프라인 구현 및 반복 개선 (피처 확장, 정규화 방식 고도화)<br>• 데이터셋 적합성 분석<br>• 여성 스트레스 데이터셋 후보 7개 검토, WESAD·WorkStress3D 선정 및 전처리 파이프라인 구현<br>• 9채널 실시간 피처 구조 설계 및 SW팀 연동 명세서 작성 <br>• 여성 대상 프로젝트 계획서/보고서 작성 | <joonseojj@gmail.com> |
| 초라핀스카 베로니카 (seennothing) | Data / AI Engineer | • 데이터셋 조사<br>• 데이터 전처리 및 데이터셋 통합<br>• 모델 학습 및 최적화<br>• 모델 성능 검증<br>• UX 중심 결과 필터링 실험 (false positive 제거 목적)<br>• ONNX export 및 SW team handoff | <czorapinska@kookmin.ac.kr> |

전체 기여자 그래프: <https://github.com/kookmin-sw/2026-capstone-18/graphs/contributors>

---

## 8. 시연 영상

<p align="center">
  <video src="https://github.com/user-attachments/assets/9077115f-dcfc-4898-a309-afc126edbf79" controls muted playsinline width="320"></video>
</p>

> 🔊 소리를 켜고 보세요.

### 주요 화면

<table>
  <tr>
    <td align="center" width="20%"><img src="docs/images/screen-home.jpg" width="180" alt="홈"/><br/><sub><b>홈</b><br/>실시간 스트레스·수면·주기</sub></td>
    <td align="center" width="20%"><img src="docs/images/screen-insights.jpg" width="180" alt="인사이트"/><br/><sub><b>인사이트</b><br/>주기 단계별 스트레스 흐름</sub></td>
    <td align="center" width="20%"><img src="docs/images/screen-profile.jpg" width="180" alt="프로필"/><br/><sub><b>프로필</b><br/>스트레스 요인 태그 관리</sub></td>
    <td align="center" width="20%"><img src="docs/images/screen-sleep.jpg" width="180" alt="수면"/><br/><sub><b>수면</b><br/>일별 수면 시간 추이</sub></td>
    <td align="center" width="20%"><img src="docs/images/screen-launcher.jpg" width="180" alt="런처"/><br/><sub><b>런처</b><br/>Galaxy 런처에 설치된 Luma</sub></td>
  </tr>
</table>

---

## 기여 가이드

`master`에 직접 푸시하지 않고 PR-only 워크플로우로 운영합니다. 브랜치 prefix(`feat/`, `fix/`, `docs/`, `chore/`, `refactor/`, `test/`, `infra/`), Conventional Commits 메시지, PR 체크리스트, 보안 영역 추가 승인 규칙은 [`CONTRIBUTING.md`](CONTRIBUTING.md)를 참고하세요.

---

## 라이선스

본 저장소는 [MIT 라이선스](LICENSE) 하에 배포됩니다.

다음 구성 요소는 별도 라이선스가 적용되며 MIT 적용 범위에서 제외됩니다.

- Samsung Health Sensor SDK (`watch/sensor-capture/libs/samsung-health-sensor-api-1.4.1.aar`) — Samsung Health SDK License Agreement
- WESAD / Stress-Predict 데이터셋 — 원본 연구용 라이선스 (자세한 내용은 `AI/src/dataset/`)
