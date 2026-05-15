# Tasks — Slice 10: Mobile (React Native)

Work through in order. Check off each task as it is completed.

---

## 1. Scaffold Expo App

Directory: `mobile/`

- [ ] `npx create-expo-app mobile --template blank-typescript`
- [ ] Install dependencies: `@rn-voice/react-native-voice`, `expo-av`, `react-native-mmkv`, `@react-native-community/background-fetch`, `@react-native-async-storage/async-storage`, `phoenix-channels-js`
- [ ] Configure `app.json`: app name "SiteVoice", bundle identifiers

## 2. Auth Module

File: `mobile/src/auth.ts`

- [ ] `login(email, password)` — POST to `/auth/user/password/sign_in`; store JWT in AsyncStorage
- [ ] `getToken()` — retrieve JWT from AsyncStorage
- [ ] `decodeToken()` — parse JWT claims; return `{ organization_id, user_id, role }`
- [ ] `logout()` — clear AsyncStorage JWT

## 3. API Client

File: `mobile/src/api.ts`

- [ ] `apiGet(path)` — GET `/api/json/{path}` with Bearer token header
- [ ] `apiPost(path, body)` — POST with JSON:API body and Bearer token
- [ ] `apiPatch(path, body)` — PATCH with JSON:API body and Bearer token

## 4. Phoenix Channel Client

File: `mobile/src/channel.ts`

- [ ] Connect to `ws://{host}/socket/websocket` with Bearer token
- [ ] `joinChannel(topic)` — join channel with `{ token: jwt }` payload; return channel instance
- [ ] `leaveChannel(channel)` — leave gracefully

## 5. HomeScreen

File: `mobile/src/screens/HomeScreen.tsx`

- [ ] Fetch today's `DailyLog` for current user on mount
- [ ] Display log status with appropriate CTA button
- [ ] Show offline queue count if any pending submissions

## 6. RecordingScreen

File: `mobile/src/screens/RecordingScreen.tsx`

- [ ] Implement `useAudioRecorder` hook: try `@rn-voice`; fall back to `expo-av`
- [ ] Record button: start/stop; show elapsed timer
- [ ] Photo picker: multi-select up to 10 images
- [ ] Submit handler: upload audio + photos; navigate to ProcessingScreen; if offline, enqueue to MMKV

## 7. Offline Queue

File: `mobile/src/offlineQueue.ts`

- [ ] `enqueue(submission)` — store to MMKV
- [ ] `dequeue()` — retrieve and remove oldest item
- [ ] `count()` — number of pending items
- [ ] BackgroundFetch task registration: replay queue on each background fetch cycle

## 8. ProcessingScreen

File: `mobile/src/screens/ProcessingScreen.tsx`

- [ ] Join `recording:{log_id}` Phoenix Channel on mount; leave on unmount
- [ ] Subscribe to `pipeline_step` and `report_ready` channel events
- [ ] Render step progress list with status icons
- [ ] Navigate to ReviewScreen on `report_ready`

## 9. ReviewScreen

File: `mobile/src/screens/ReviewScreen.tsx`

- [ ] Fetch `DailyLog` with structured fields
- [ ] Render summary, work items, safety notes, weather, transcript sections
- [ ] "Download PDF" — `Linking.openURL(pdf_url)`
- [ ] "Submit" button — PATCH `:approve_and_submit`; navigate to SuccessScreen

## 10. SuccessScreen

File: `mobile/src/screens/SuccessScreen.tsx`

- [ ] Confirmation message
- [ ] "Back to Home" button — navigate to HomeScreen and reset stack

## 11. Navigation

File: `mobile/src/navigation.tsx`

- [ ] Stack navigator: Login → Home → Recording → Processing → Review → Success
- [ ] Auth guard: redirect to Login if no stored JWT

## 12. Backend Integration Tests

File: `test/sitevoice_web/channels/mobile_integration_test.exs`

- [ ] Tag `@moduletag slice: :mobile`
- [ ] Test channel join with valid JWT
- [ ] Test channel join rejected with invalid JWT
- [ ] Test `pipeline_step` broadcast received by connected client
- [ ] Test `report_ready` broadcast received by connected client

## 13. React Native Unit Tests

Files: `mobile/src/__tests__/`

- [ ] `auth.test.ts` — login, token decode, logout
- [ ] `offlineQueue.test.ts` — enqueue, dequeue, count
- [ ] `api.test.ts` — request construction with Bearer header

## 14. Verify

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:mobile` — backend integration tests pass
- [ ] `cd mobile && npx jest` — React Native unit tests pass
- [ ] `mix test` — no regressions in slices 00–09
