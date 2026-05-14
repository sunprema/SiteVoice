# Coding Standards — SiteVoice AI

## Ash Resources

- Always define actions explicitly — never use `defaults [:read, :create]` alone
- Every action must have at least one matching policy
- Use `Ash.Changeset.manage_relationship` for relationship changes
- Changes go in `lib/sitevoice/domain/resources/changes/`
- Calculations go in `lib/sitevoice/domain/resources/calculations/`

## Reactor Steps

- One file per step: `lib/sitevoice/reporting/steps/step_name.ex`
- Always implement `compensate/4` for steps that mutate state
- Steps that call external APIs must have a timeout set
- Use `async?: true` only when the step truly has no dependency on concurrent steps
- Never call Oban from inside a Reactor step — broadcast via PubSub instead

## Testing

- Use `Ash.Test` helpers for resource action tests
- Tag all tests by slice: `@moduletag slice: :transcription`
- External API calls: use `Req.Test` stubs, never real endpoints in tests
- Every Reactor must have an integration test that runs the full pipeline
- Use `Oban.Testing` for job tests

## File Naming Conventions

lib/sitevoice/
accounts/
resources/
user.ex
token.ex
changes/
hash_password.ex
reporting/
resources/
daily_log.ex
photo.ex
reactors/
process_recording.ex
steps/
transcribe_whisper.ex
structure_with_claude.ex
caption_photos.ex
generate_pdf.ex
store_tigris.ex
broadcast_ready.ex
workers/
audio_processor.ex

## Typst Templates

- All templates in `priv/templates/`
- One template per document type
- Data keys always snake_case strings (Imprintor requirement)

## Environment / Config

- All secrets via `Application.fetch_env!/2` in runtime.exs
- Never `Application.get_env` with a default for secrets
- Config modules in `lib/sitevoice/config.ex` for typed access
