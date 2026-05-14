# CLAUDE.md SiteVoice

## What This Project Is

SiteVoice converts construction field voice memos into professional daily logs.
Foremen speak for 90 seconds. The system produces a structured PDF report in under 30 seconds.

Full specification: `docs/APPLICATION_SPEC.md`

## How To Work On This Project

**Always work in slices.** Never work across multiple slices in one session.

Each slice in `slices/NN-name/` contains three files:

- `CONTEXT.md` — read this first; tells you exactly which spec sections and files to load
- `SLICE.md` — what to build and the acceptance criteria
- `TASKS.md` — ordered checklist of concrete tasks to execute

### Session Start Protocol

Every session:

1. Ask which slice to work on (if not told)
2. Read `slices/NN-name/CONTEXT.md` — load only what it specifies
3. Read `slices/NN-name/SLICE.md` — understand what done looks like
4. Read `slices/NN-name/TASKS.md` — work through tasks in order
5. Check off tasks as you complete them
6. Run tests before declaring a slice done

---

## Slice Execution Order

Hand off one slice at a time. Each is independently deployable and testable
before the next begins. Do not start a slice until its dependencies are marked complete.

```
00 → Foundation
     Umbrella app, all dependencies, config, Repo, Tigris storage module,
     Organization resource (tenant root), Oban queues, mix ash.setup working.
     ⚠ Multitenancy foundation must be established here before any other domain resource.

01 → Auth
     AshAuthentication, User resource (tenanted), JWT with organization_id claim,
     SetTenant plug, VerifyToken plug, registration flow (org + first user).

02 → Projects
     Project resource (tenanted), ProjectMembership (tenanted),
     AshJsonApi endpoints, Ash Policies.

03 → Recording
     DailyLog resource (tenanted), :submit_recording action,
     audio upload to Tigris (org-prefixed keys), Phoenix Channel scaffold.

04 → AI Pipeline
     Ash Reactor (ProcessRecording), SetTenant step, Whisper transcription,
     Claude structuring, photo captioning, Oban worker, pipeline status broadcasts.

05 → PDF Generation
     Imprintor integration, Typst daily_log.typ template,
     PDF stored to Tigris (org-prefixed), PDF URL on DailyLog.

06 → Real-time
     Phoenix Channels complete (RecordingChannel, LogChannel),
     org-namespaced PubSub topics, pipeline step broadcasts, PM dashboard feed.

07 → Notifications
     Swoosh email (daily log PDF to PM), push notification on report ready,
     DailyReminderWorker (Oban cron).

08 → Integrations
     Integration resource (tenanted), Procore adapter,
     IntegrationEvent resource, post-submission dispatch.

09 → Mobile (React Native)
     All screens (Home, Recording, Processing, Review, Success),
     dual audio strategy (@rn-voice + expo-av), offline queue (MMKV + BackgroundFetch),
     Phoenix Channel client, JWT storage and attachment.
```

### Slice Status

Update this table as slices are completed:

| Slice | Name           | Status         |
| ----- | -------------- | -------------- |
| 00    | Foundation     | ✅ Complete    |
| 01    | Auth           | ⬜ Not started |
| 02    | Projects       | ⬜ Not started |
| 03    | Recording      | ⬜ Not started |
| 04    | AI Pipeline    | ⬜ Not started |
| 05    | PDF Generation | ⬜ Not started |
| 06    | Real-time      | ⬜ Not started |
| 07    | Notifications  | ⬜ Not started |
| 08    | Integrations   | ⬜ Not started |
| 09    | Mobile         | ⬜ Not started |

---

## Architecture Rules (Never Violate)

### Ash

- Never write Phoenix controllers for Ash resources — use AshJsonApi
- Never write raw Ecto queries — go through Ash actions
- Never skip Ash Policies — every action needs authorization
- Never use `defaults [:read, :create]` alone — define actions explicitly
- Always put Changes in `lib/site_voice/domain/resources/changes/`
- Always put Calculations in `lib/site_voice/domain/resources/calculations/`

### Multitenancy

- Every tenanted resource must have a `multitenancy do strategy :attribute; attribute :organization_id end` block
- `organization_id` is NEVER accepted from client request bodies — JWT only
- `Ash.set_tenant/1` must be called at every process boundary:
  - HTTP request → SetTenant plug
  - Phoenix Channel join → explicit call
  - Phoenix Channel handle_in → re-call every time
  - Oban worker perform/1 → first line, always
  - Ash Reactor → SetTenant step with wait_for on all Ash steps
  - Task.async → pass org_id, call inside task
- All Oban job args must include `organization_id`
- All Tigris storage keys must be prefixed `{organization_id}/...`
- All PubSub topics must be `"org:{org_id}:{resource}:{id}"` — never bare

### Reactor

- One file per step: `lib/site_voice/reporting/steps/step_name.ex`
- Always implement `compensate/4` for steps that mutate state
- External API steps must have a timeout
- `async?: true` only when the step has no dependency on concurrent steps
- Never call Oban from inside a Reactor step

### Oban

- Every worker's `perform/1` calls `Ash.set_tenant(args["organization_id"])` as its first line
- Never perform long-running work synchronously in a Phoenix Channel or controller
- Always use `max_attempts: 3` minimum

### Testing

- Tag all tests by slice: `@moduletag slice: :auth`
- External API calls: use `Req.Test` stubs — never real endpoints in test env
- Every Reactor must have an integration test running the full pipeline
- Use `Oban.Testing` for job tests
- Use `Ash.Test` helpers for resource action tests

---

## What To Never Do

- Never hardcode credentials — use `Application.fetch_env!/2`
- Never expose the `SiteVoice.Admin` domain via the public AshJsonApi router
- Never use bare PubSub topics without `org:{org_id}:` prefix
- Never pass `organization_id` in API request bodies — JWT only
- Never run Whisper or Claude calls synchronously in a request handler
- Never create a new process (Task, GenServer) without propagating `organization_id`

---

## Running The Project

```bash
mix deps.get
mix ash.setup          # creates DB, runs migrations, seeds
mix phx.server         # starts Phoenix on port 4000
```

## Running Tests

```bash
mix test                              # all tests
mix test --only slice:auth            # specific slice
mix test slices/01-auth/              # slice directory
```

## Generating Ash Resources

```bash
mix ash.gen.resource SiteVoice.Reporting.DailyLog
```

Always read `docs/CODING_STANDARDS.md` before generating a resource.
Always add the `multitenancy` block to every tenanted resource immediately after generation.

---

## Key Environment Variables

```bash
DATABASE_URL             # PostgreSQL connection
AWS_ACCESS_KEY_ID     # Tigris storage
AWS_SECRET_ACCESS_KEY
OPENAI_API_KEY           # Whisper transcription
ANTHROPIC_API_KEY        # Claude structuring
SECRET_KEY_BASE
TOKEN_SIGNING_SECRET     # AshAuthentication JWT
PHX_HOST
RESEND_API_KEY           # Email
```

---

## Docs Index

| Document                                 | Purpose                                        |
| ---------------------------------------- | ---------------------------------------------- |
| `docs/APPLICATION_SPEC.md`               | Full technical specification (source of truth) |
| `docs/ARCHITECTURE.md`                   | System diagrams and data flow                  |
| `docs/CODING_STANDARDS.md`               | Elixir/Ash/Reactor conventions and file layout |
| `docs/DOMAIN_MODEL.md`                   | Ash resource definitions and relationships     |
| `docs/adr/001-whisper.md`                | Why attribute strategy (row-level)             |
| `docs/adr/002-multitenancy.md`           | Why JSON:API for mobile                        |
| `docs/adr/001-multitenancy-attribute.md` | Why attribute strategy (row-level)             |
| `docs/adr/002-jsonapi-mobile.md`         | Why JSON:API for mobile                        |

---

## Stack Quick Reference

| Layer          | Choice                                              |
| -------------- | --------------------------------------------------- |
| Mobile         | React Native + Expo                                 |
| Backend        | Phoenix + Elixir                                    |
| Domain         | Ash Framework 3.x + Spark DSL                       |
| Multitenancy   | Ash attribute strategy (row-level, organization_id) |
| Pipeline       | Ash Reactor                                         |
| API            | AshJsonApi (JSON:API)                               |
| Auth           | AshAuthentication + Ash Policies                    |
| Audit          | Ash Paper Trail                                     |
| Jobs           | Oban (Postgres-backed)                              |
| Transcription  | OpenAI Whisper API (MVP)                            |
| AI Structuring | Anthropic Claude claude-sonnet-4-20250514           |
| Database       | PostgreSQL 16+ + AshPostgres                        |
| Storage        | Tigris (ex_aws_s3, org-prefixed keys)               |
| PDF            | Imprintor (Typst + Rust, PDF/A-3a)                  |
| Email          | Swoosh                                              |
| Real-time      | Phoenix Channels + PubSub (org-namespaced)          |

## HTTP REQUEST LIBRARY

- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

<!-- usage-rules-start -->
<!-- usage_rules-start -->

## usage_rules usage

_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should _thoroughly_ consult before taking any
action. These usage rules contain guidelines and rules _directly from the package authors_.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```

## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```

## Elixir library reference

If you need additional documentation, elixir libraries are installed under deps/<library_name>. You will find README.md under that.
<library_documentation_example>
library name: spark
documentation: `deps/spark/README.md`
</library_documentation_example>

<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->

## usage_rules:elixir usage

# Elixir Core Usage Rules

## Pattern Matching

- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling

- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid

- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design

- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures

- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->

## usage_rules:otp usage

# OTP Usage Rules

## GenServer Best Practices

- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication

- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance

- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async

- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
