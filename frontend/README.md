# Luma Frontend

## Overview

`frontend/`는 Luma의 Flutter 기반 Android app입니다. 사용자-facing 화면에서 stress logging, cycle-aware insight, sleep UI, notification registration, wearable-oriented biosignal capture UI를 담당합니다.

앱은 staging backend와 REST API로 통신하며, Provider 기반 상태 관리로 화면과 data/API/native layer를 연결합니다. Root README가 전체 프로젝트 showcase 문서라면, 이 문서는 frontend module을 실행하고 구조를 이해하고 검증하기 위한 engineering README입니다.

## Tech Stack

| 영역 | 기술 |
| :--- | :--- |
| App framework | Flutter / Dart |
| State management | Provider |
| Backend communication | REST API client layer |
| Push registration | Firebase Messaging / FCM |
| Auth frontend flow | Google Sign-In frontend flow, anonymous auth |
| Native bridge | MethodChannel / EventChannel |
| Native integration | Android foreground service |
| Wear boundary | Wear Data Layer |
| Android package | `com.littlesignals.app` |

## Project Structure

```text
frontend/
├── lib/
│   ├── core/       # app config, ApiClient, secure storage, theme, shared widgets, UI formatters
│   ├── features/   # domain providers, models, API adapters, services
│   └── screens/    # Home, Insight, My/Profile, Stress Log, Cycle, Sleep, Watch UI
├── android/        # Android package, native capture service, Wear Data Layer boundary
└── test/           # Flutter unit/widget/regression smoke tests
```

`lib/core`는 공통 기반 계층입니다. API base URL, token storage, shared HTTP client, theme, reusable widgets, Korean UI text formatter를 둡니다.

`lib/features`는 domain별 provider와 data adapter를 둡니다. UI는 provider state를 읽고, provider는 `features/*/data` API adapter 또는 native service를 호출합니다.

`lib/screens`는 실제 화면 composition을 담당합니다. 화면은 backend endpoint를 직접 다루지 않고 Provider state와 action을 사용합니다.

`android`는 Flutter app의 Android runtime과 native capture layer를 포함합니다. `test`는 app flow, provider behavior, formatter, notification copy, native bridge controller 등을 검증합니다.

## Implemented Features

- Auth landing
- Anonymous auth
- Google Sign-In frontend request flow
- Home dashboard
- Stress log create/edit
- Trigger/category management
- Cycle current/history/create/update flow
- My Cycle auto-save UX
- Sleep log display states
- Insight calendar / report UI
- AI selected-period report card/detail UI
- Profile / nickname editing
- Notification permission
- FCM device token registration
- Watch / biosignal capture UI
- Raw biosignal consent toggle
- Capture source picker
- Capture status / summary screen
- Korean UI copy polish
- Regression smoke tests

## Backend APIs Used

Frontend에서 사용하는 주요 backend API는 다음과 같습니다.

| 기능 | API |
| :--- | :--- |
| User profile | `/api/v1/me` |
| Stress events | `/api/v1/events` |
| Cycle current | `/api/v1/cycles/current` |
| Cycle history | `/api/v1/cycles/history` |
| Trigger/category | `/api/v1/categories` |
| Consent | `/api/v1/consent` |
| Sleep latest | `/api/v1/sleep-logs/latest` |
| FCM device token | `/api/v1/devices/fcm-token` |
| AI selected-period report | `/api/v1/reports/range` |
| Biosignal batch metadata | `/api/v1/sync/biosignals/batch` |
| Raw biosignal object upload | presigned S3 PUT upload flow |

API base URL은 `lib/core/config/api_config.dart`에서 관리합니다. Shared `ApiClient`는 request ID, JSON decode, auth header, token refresh, error mapping을 담당합니다.

## Native Capture Infrastructure

Luma frontend에는 wearable-oriented biosignal capture infrastructure가 포함되어 있습니다. 이 범위는 raw biosignal capture/upload UX와 phone-side native plumbing을 설명합니다.

- Flutter `BiosignalCaptureService`
  - `MethodChannel('littlesignals/capture')`
  - `EventChannel('littlesignals/capture/status')`
  - `start`, `stop`, `isWatchConnected`, `statusStream`
- Flutter `BiosignalCaptureController`
  - capture state, elapsed seconds, uploaded window count, error, watch connection state 노출
- Android `BiosignalCaptureService`
  - foreground service로 capture session 실행
- Wear Data Layer messaging
  - `WearMessageClient`가 reachable node/capability 확인과 `/biosignals/start`, `/biosignals/stop` 전송 담당
- `WatchSampleReceiver`
  - `/biosignals/samples`, `/biosignals/end` message 수신
- `WatchSourceController`
  - HR, PPG, EDA, accelerometer sample buffering
- `SyntheticSampleSource`
  - capture/upload plumbing 확인용 synthetic source
- `WindowUploader`
  - 1분 단위 window 생성
  - `/api/v1/sync/biosignals/batch` 호출
  - backend가 반환한 presigned S3 PUT URL로 raw payload 업로드
- Capture summary UI
  - elapsed time, uploaded window count, estimated data size 표시

간단한 흐름은 다음과 같습니다.

```mermaid
flowchart LR
    UI["Flutter Watch UI"] --> Bridge["MethodChannel / EventChannel"]
    Bridge --> Service["Android foreground service"]
    Service --> Source{"Capture source"}
    Source --> Wear["Wear Data Layer"]
    Source --> Synthetic["SyntheticSampleSource"]
    Wear --> Receiver["WatchSampleReceiver"]
    Receiver --> Buffer["WatchSourceController"]
    Synthetic --> Uploader["WindowUploader"]
    Buffer --> Uploader
    Uploader --> Batch["/api/v1/sync/biosignals/batch"]
    Batch --> S3["Presigned S3 PUT"]
```

## Running

```bash
cd frontend
flutter pub get
flutter run
```

Google OAuth web client ID를 runtime에 지정할 때:

```bash
flutter run --dart-define=LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

## Testing

```bash
flutter analyze
flutter test
```

Regression smoke tests는 auth navigation, anonymous auth, main tabs, Home dashboard, stress log create/edit, trigger management, cycle auto-save, sleep display states, notification copy, nickname/session cleanup, provider reset 같은 주요 app flow를 검증합니다.

Android native unit tests는 Android project에서 실행할 수 있습니다.

```bash
cd android
./gradlew testDebugUnitTest
```

## Configuration Notes

- 사용자-facing branding은 `Luma`입니다.
- Android package는 현재 `com.littlesignals.app`입니다.
- Google OAuth runtime env key는 현재 `LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID`입니다.
- Android package 및 일부 runtime env key는 build/runtime compatibility를 위해 유지됩니다.

다음 local secret 또는 generated file은 commit하지 않습니다.

- `google-services.json`
- `GoogleService-Info.plist`
- `firebase_options.dart`
- `.env`
- `.env.*`
- `key.properties`
- `*.keystore`
- `*.jks`
