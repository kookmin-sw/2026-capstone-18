[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/Lvs6kcL8)
# Welcome to GitHub

캡스톤 팀 생성을 축하합니다.

## 팀소개 및 페이지를 꾸며주세요.

- 프로젝트 소개
  - 프로젝트 설치방법 및 데모, 사용방법, 프리뷰등을 readme.md에 작성.
  - Api나 사용방법등 내용이 많을경우 wiki에 꾸미고 링크 추가.

- 팀페이지 꾸미기
  - 프로젝트 소개 및 팀원 소개
  - index.md 예시보고 수정.

- GitHub Pages 리파지토리 Settings > Options > GitHub Pages 
  - Source를 marster branch
  - Theme Chooser에서 태마선택
  - 수정후 팀페이지 확인하여 점검.

**팀페이지 주소** -> https://kookmin-sw.github.io/ '{{자신의 리파지토리 아이디}}'

**예시)** 2023년 0조  https://kookmin-sw.github.io/capstone-2023-00/


## 내용에 아래와 같은 내용들을 추가하세요.

### 1. 프로잭트 소개

본 저장소는 WESAD 데이터셋을 활용하여 사전 스트레스(Pre-Stress)를 예측하기 위해 최적화되고 배포 준비가 완료된 시계열 분류(TSC, Time Series Classification) Mamba 파이프라인을 포함하고 있습니다. 

이 v2 아키텍처는 명시적인 수학적 피처 주입(Feature Injection)과 간소화된 3-Class 상태 머신을 활용하여, 엣지 환경(예: Flutter 애플리케이션)에서의 효율적인 배포를 목적으로 특별히 설계되었습니다.

### 주요 기술적 성과 
* **9-채널 명시적 피처 주입 (Explicit Feature Injection):** 모델이 고주파 노이즈로부터 거시적 추세를 강제로 학습하게 하는 대신, 인과적 지수이동평균(Causal EMA) 및 MACD Delta 기울기를 입력 텐서에 직접 주입합니다.
* **배포 지향적 3-Class 시스템:** 노이즈가 많은 기존 5-Class WESAD 프로토콜을 견고한 3-Class 시스템(`0: Baseline`, `1: Pre-Stress`, `2: Stress`)으로 통합했습니다. 사후 스트레스 회복(Cooldown)과 즐거움(Amusement) 상태는 INT8 양자화 경계를 보존하기 위해 알고리즘적으로 Baseline에 매핑됩니다.
* **Causal MACD 동적 라벨링:** 생리학적 각성 상태의 정확한 시작점을 수학적으로 특정하기 위해, 10초간의 템포럴 디바운싱(Temporal Debouncing)이 적용된 엄격한 인과적 10분 룩백(Lookback) 알고리즘을 구현했습니다.
* **Pure PyTorch Mamba:** 제한된 엣지 환경에서의 호환성을 극대화하기 위해 `mamba-ssm` 패키지에 의존하지 않는 순수 PyTorch 구현체를 사용합니다.

### 2. 소개 영상

프로젝트 소개하는 영상을 추가하세요

### 3. 팀 소개

팀을 소개하세요.

팀원정보 및 담당이나 사진 및 SNS를 이용하여 소개하세요.

### 4. 사용법

소스코드제출시 설치법이나 사용법을 작성하세요.

### 저장소 구조
```text
meltdownguard-mamba/
├── README.md
├── .gitignore
├── notebooks/
│   └── eval_scripts.ipynb   # 시각화 및 평가 스크립트
└── src/
    ├── download.py          # Kagglehub 기반 WESAD 자동 다운로드 스크립트
    ├── preprocess.py        # 9-채널 3-Class 데이터 전처리 파이프라인
    ├── mamba_model.py       # Pure PyTorch Mamba 아키텍처
    └── train.py             # 학습 루프 및 KFold 교차 검증
```

### 빠른 시작 가이드 (Quick Start Guide)

**Step 1. 데이터셋 다운로드**
`kagglehub`를 사용하여 WESAD 데이터셋을 안전하게 다운로드하고 지정된 로컬 디렉토리로 이동시킵니다.

```bash
python src/download.py
```

**Step 2. 전처리 파이프라인 실행**
원본 신호를 캘리브레이션하고, True IIR EMA 및 MACD 채널을 계산하며, 3-Class 동적 라벨링을 적용한 후 60초 청크(stride: 5초)를 추출하여 `.npy` 텐서로 저장합니다.

```bash
python src/preprocess.py
```

**Step 3. 모델 학습**
피험자 간 데이터 누수(Data Leakage)를 방지하기 위해 결정론적인 5-Fold GroupKFold 검증 전략을 사용하여 모델을 학습시킵니다.

```bash
python src/train.py --epochs 50 --batch_size 64
```
*(Tip: 학습이 예기치 않게 중단된 경우, `--resume` 플래그를 추가하여 안전하게 학습을 재개하고 로그를 복구할 수 있습니다.)*

**Step 4. 평가 및 시각화**
학습이 완료되면 `notebooks/eval_scripts.ipynb` 파일을 열어 Scikit-Learn 분류 보고서, Ground Truth과 Mamba 예측 결과를 비교하는 피험자별 타임라인 그래프 등 확인할 수 있습니다.

### 5. 기타

추가적인 내용은 자유롭게 작성하세요.


## Markdown을 사용하여 내용꾸미기

Markdown은 작문을 스타일링하기위한 가볍고 사용하기 쉬운 구문입니다. 여기에는 다음을위한 규칙이 포함됩니다.

```markdown
Syntax highlighted code block

# Header 1
## Header 2
### Header 3

- Bulleted
- List

1. Numbered
2. List

**Bold** and _Italic_ and `Code` text

[Link](url) and ![Image](src)
```

자세한 내용은 [GitHub Flavored Markdown](https://guides.github.com/features/mastering-markdown/).

### Support or Contact

readme 파일 생성에 추가적인 도움이 필요하면 [도움말](https://help.github.com/articles/about-readmes/) 이나 [contact support](https://github.com/contact) 을 이용하세요.
