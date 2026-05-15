# Slice 10 — Mobile (React Native)

**Goal:** Build the React Native + Expo mobile application. Foremen record a 90-second voice memo,
attach site photos, and submit. The app shows real-time pipeline progress via Phoenix Channel,
then displays the structured log for review. An offline queue handles submissions when connectivity
is unavailable.

## Acceptance Criteria

### Auth

- [ ] Login screen: email + password; calls `/auth/user/password/sign_in`; stores JWT in AsyncStorage
- [ ] JWT decoded client-side to extract `organization_id` and `user_id` claims
- [ ] All API requests include `Authorization: Bearer {jwt}` header

### HomeScreen

- [ ] Shows today's log status (no log / processing / ready / submitted)
- [ ] "Record" button navigates to RecordingScreen
- [ ] If log is `:ready`, shows "Review" button navigating to ReviewScreen

### RecordingScreen

- [ ] Start/stop recording button; shows elapsed time
- [ ] Primary audio strategy: `@rn-voice` — records to local file
- [ ] Fallback audio strategy: `expo-av` — activated if `@rn-voice` fails to initialize
- [ ] Photo picker: multi-select up to 10 images from camera roll
- [ ] "Submit" button: uploads audio + photos to backend via multipart JSON:API call; navigates to ProcessingScreen
- [ ] If offline: enqueues submission to MMKV offline queue; shows "Queued for sync" message

### ProcessingScreen

- [ ] Connects to Phoenix Channel `recording:{log_id}` on mount
- [ ] Joins with `%{"token" => jwt}` payload
- [ ] Displays step-by-step pipeline progress: transcription → structuring → photo captioning → PDF
- [ ] Handles `pipeline_step` channel push; handles `report_ready` push → navigates to ReviewScreen

### ReviewScreen

- [ ] Displays structured log fields: summary, work items, safety notes, weather, transcript
- [ ] "Download PDF" button — opens presigned PDF URL in device browser
- [ ] "Submit" button (foreman): calls `:approve_and_submit` via JSON:API; navigates to SuccessScreen

### SuccessScreen

- [ ] Confirmation message with date and project name
- [ ] "Back to Home" navigation

### Offline Queue

- [ ] Pending submissions stored in MMKV with full payload (audio path, photo paths, project_id)
- [ ] `BackgroundFetch` task: on connectivity restored, replay queued submissions in order
- [ ] Queued items visible on HomeScreen with "Pending sync" indicator

### General

- [ ] `mix test --only slice:mobile` — backend channel/API integration tests pass
- [ ] React Native unit tests: `cd mobile && npx jest` — all pass
- [ ] `mix test` — no regressions in slices 00–09

## What This Slice Does NOT Include

- Push notification handling beyond what Slice 07 already broadcasts
- In-app PDF viewer (opens in device browser)
- Admin or PM management screens (use LiveView from Slice 08 for that)
- Procore integration UI (Slice 09 handles backend dispatch automatically)
