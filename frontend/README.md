# LittleSignals Flutter Frontend

## Overview

LittleSignals is a Flutter mobile app for visualizing women's stress logs, menstrual cycle context, and sleep data flows. The current frontend uses a provider-driven architecture wired to the staging API.

The app is structured to support future Galaxy Watch, Health Connect, or Samsung Health ingestion, but native watch data ingestion is not implemented yet.

## Current Implemented Features

- Auth landing flow
- Anonymous login
- Google Sign-In frontend flow with account picker, `idToken` retrieval, and backend request to `POST /api/v1/auth/google`
- Home dashboard for stress, cycle, and recent activity context
- Stress log create and edit flow
- Trigger management, including default trigger merge behavior and duplicate validation
- Cycle tracking with date selection and auto-save UX
- Sleep page empty state and populated state UI
- Insight calendar and cycle/stress insight UI
- Profile nickname editing with raw nickname storage and Korean display polish
- Notification permission request and FCM device token registration pipeline
- Korean UI copy polish for MVP flows
- Regression smoke tests for core navigation and user flows
- Session cleanup and provider reset on auth state changes
- Staging API integration

## Architecture

- Flutter mobile frontend
- Provider-based state management
- API client layer for staging backend integration
- Provider-driven UI state for auth, home, stress events, cycle, sleep, triggers, insight, consent, and future settings preferences
- Service contracts for future Watch/Sleep/Cycle integration

The frontend keeps UI and provider state separate from backend transport details. API adapters own request/response mapping, while screens consume provider state.

## Integration Status

### Implemented

- Anonymous auth
- Google Sign-In frontend request flow
- Staging API connectivity
- FCM device token registration pipeline
- Stress events create/list/update/delete flow
- Cycle create/history/current/update flow
- Sleep log create/list/latest/update/delete provider flow
- Session lifecycle cleanup across providers

### Pending / Next Stage

- Backend Google OAuth audience/client alignment for staging `invalid_google_token` cases
- Email/password auth endpoints
- Real Galaxy Watch data ingestion
- Health Connect or Samsung Health data source integration
- Native Android bridge or MethodChannel integration
- End-to-end push notification delivery verification

The frontend is integration-ready for watch-driven sleep and cycle data, but native ingestion is still pending.

## Watch / Sleep / Cycle Contract

`WatchSleepService.getLatestSleepData()` is the frontend boundary for future sleep ingestion. The provider expects a `WatchSleepData` model with:

- `fellAsleepAt`
- `wokeUpAt`
- `endedOn`

`WatchCycleService.getLatestCycleData()` is the frontend boundary for future cycle ingestion. The provider expects a `WatchCycleData` model with:

- `periodStart`
- `periodEnd`
- `estimatedCycleLength`

Once a native data source is connected, these service contracts can provide watch or health-platform data to the existing provider/UI flow without redesigning the screens.

## Running the App

Install dependencies:

```bash
flutter pub get
```

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Run the app:

```bash
flutter run
```

Run with an explicit Google web client ID override:

```bash
flutter run --dart-define=LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

## Google Login Configuration

The Google Sign-In frontend flow is wired for the current integration state:

- Google account picker opens through the Flutter client.
- The frontend requests a Google `idToken`.
- The token is sent to `POST /api/v1/auth/google`.
- An `invalid_google_token` response from staging indicates backend OAuth client/audience alignment needs to be checked.

For real Google login, confirm that Firebase and backend OAuth configuration use the same web client ID expected by the Flutter app as `serverClientId`.

## Configuration / Secrets

Do not commit local secrets or generated service files:

- `google-services.json`
- `GoogleService-Info.plist`
- `firebase_options.dart`
- `.env`
- `.env.*`
- `key.properties`
- `*.keystore`
- `*.jks`

The base URL and websocket URL are configured in `lib/core/config/api_config.dart`.

## Testing

Use the standard Flutter checks:

```bash
flutter analyze
flutter test
```

Regression smoke tests cover:

- auth landing and login navigation
- main tab navigation
- cycle tracking and auto-save
- sleep screens
- trigger management
- stress log creation/editing
- notification copy
- nickname and session cleanup behavior

## Notes

- Frontend naming, configuration, and documentation are standardized under the LittleSignals project name.
- Do not describe Galaxy Watch integration as complete until native data ingestion is connected and verified.
- Current watch-related frontend architecture is contract-ready; actual native ingestion remains a next-stage integration task.
