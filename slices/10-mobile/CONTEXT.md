# Context — Slice 10: Mobile (React Native)

## Dependency

Slice 09 (Integrations) must be complete before starting this slice.

## Purpose

This slice builds the React Native + Expo mobile application. Foremen use it to record audio,
attach photos, and submit daily logs. The app connects to the Phoenix Channel backend built in
Slices 03 and 06 for real-time pipeline status.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §17 — Mobile: screens, navigation, dual audio strategy
2. `docs/APPLICATION_SPEC.md` §9 — Phoenix Channels: join payload, handle_in events, broadcasts
3. `docs/APPLICATION_SPEC.md` §6 — Real-time: PubSub topic naming and broadcast payloads
4. `docs/APPLICATION_SPEC.md` §2 — Auth: JWT storage, `organization_id` claim
5. `docs/CODING_STANDARDS.md` — API conventions, AshJsonApi endpoint shapes

## Existing State (Backend — all complete)

- JSON:API endpoints at `/api/json/` — Projects, DailyLogs, Photos
- AshAuthentication token endpoint at `/auth/user/password/sign_in` — returns JWT
- Phoenix Channel at `ws://host/socket/websocket` — `RecordingChannel` and `LogChannel`
- PubSub broadcasts: `{:pipeline_step, step, status}` and `{:report_ready, log}`

## Mobile App Location

All mobile code lives in `mobile/` at the project root.

## Key Screens

- `HomeScreen` — today's log status; quick record button
- `RecordingScreen` — audio recording UI with `@rn-voice` + `expo-av` fallback
- `ProcessingScreen` — real-time pipeline step progress via Phoenix Channel
- `ReviewScreen` — display structured log; approve/submit button (foreman view)
- `SuccessScreen` — confirmation after submission

## Key Libraries (mobile)

- `@rn-voice/react-native-voice` — primary audio recording
- `expo-av` — fallback audio recording strategy
- `react-native-mmkv` — offline queue storage
- `@react-native-community/background-fetch` — background sync for offline queue
- `phoenix-channels-js` — Phoenix Channel client
- `@react-native-async-storage/async-storage` — JWT storage

## Key Constraints

- JWT stored securely; `organization_id` extracted from token claims (never hardcoded)
- Offline queue: store pending log submissions in MMKV; replay via BackgroundFetch when online
- Audio strategy: try `@rn-voice` first; fall back to `expo-av` on failure
- All API calls include `Authorization: Bearer {jwt}` header
- Channel join payload: `%{"token" => jwt}`
- All tests tagged `@moduletag slice: :mobile` (backend integration tests only — React Native unit tests use Jest)
