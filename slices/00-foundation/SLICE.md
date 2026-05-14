# Slice 00 — Foundation

**Goal:** Umbrella app scaffold, database, config, and shared infrastructure.
Nothing domain-specific. Everything else depends on this.

## Acceptance Criteria

- [ ] All dependencies added to mix.exs and compiling cleanly
- [ ] AshPostgres repo configured and connected to PostgreSQL
- [ ] Tigris storage module working (can put/get a test object)
- [ ] Config structure in place for all environments
- [ ] Oban configured with all queues defined
- [ ] `mix ash.setup` runs successfully from clean state

## What This Slice Does NOT Include

- No business domains (that's slices 01–08)
- No auth (slice 01)
- No API routes (slice-specific)

## Dependencies

- None — this is the bas
