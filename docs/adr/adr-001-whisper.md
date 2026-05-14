# ADR 001 — Whisper: Hosted API for MVP

**Date:** May 2025
**Status:** Accepted

## Decision

Use OpenAI Whisper API (`whisper-1`) for MVP transcription.

## Why

- Zero infrastructure to manage during validation phase
- $0.006/min cost is negligible at MVP scale (<200 foremen)
- Faster to ship — one Reactor step, one HTTP call

## Migration Trigger

Migrate to self-hosted `large-v3-turbo` via Rust NIF when:

- First Enterprise client requests on-premise audio processing, OR
- Monthly Whisper API cost exceeds $500

## Consequences

- Audio leaves our infrastructure (acceptable for Pro tier)
- Enterprise clients must be on self-hosted before signing
- Migration path is isolated to one Reactor step — zero other changes

## See Also

- APPLICATION_SPEC.md § 9.1
- slices/04-transcription/SLICE.md
