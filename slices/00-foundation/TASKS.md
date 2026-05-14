# Tasks — Slice 00: Foundation

## 1. Dependencies (mix.exs)

If the application uses latest version and has the dependency installed already, you should use that.

- [ ] `{:ash, "~> 3.0"}`
- [ ] `{:ash_postgres, "~> 2.0"}`
- [ ] `{:ash_json_api, "~> 1.0"}`
- [ ] `{:ash_authentication, "~> 4.0"}`
- [ ] `{:ash_authentication_phoenix, "~> 2.0"}`
- [ ] `{:ash_paper_trail, "~> 0.1"}`
- [ ] `{:reactor, "~> 0.9"}`
- [ ] `{:oban, "~> 2.17"}`
- [ ] `{:req, "~> 0.5"}`
- [ ] `{:ex_aws, "~> 2.5"}`
- [ ] `{:ex_aws_s3, "~> 2.5"}`
- [ ] `{:imprintor, "~> 0.6"}`
- [ ] `{:swoosh, "~> 1.16"}`
- [ ] `{:jason, "~> 1.4"}`

## 2. Config

- [ ] `config/config.exs` — Ash, Oban queue definitions
- [ ] `config/dev.exs` — local DB, disable emails
- [ ] `config/runtime.exs` — Tigris, OpenAI, Anthropic keys from env
- [ ] `config/test.exs` — sandbox mode, mock external APIs

## 3. Repo & Database

- [ ] `SiteVoice.Repo` module (AshPostgres)
- [ ] `mix ecto.create` working
- [ ] Oban migrations added

## 4. Storage Module

- [ ] `SiteVoice.Storage` module (ex_aws_s3 + Tigris config)
- [ ] `store/3`, `fetch/2`, `presigned_url/3` functions
- [ ] Test: can upload and retrieve a test binary

## 5. Oban

- [ ] Queues defined: audio, ai, pdf, integrations, notifications
- [ ] Oban.Testing configured for test env

## 6. Verify

- [ ] `mix compile` — zero warnings
- [ ] `mix ash.setup` — runs clean
- [ ] `mix test` — foundation tests passing
