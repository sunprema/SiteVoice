# ADR 002 — Multitenancy Strategy: Attribute (Row-Level)

**Date:** May 2025
**Status:** Accepted

## Decision

Use Ash attribute-based multitenancy (row-level, organization_id column)
rather than schema-per-tenant (context strategy).

## Why

- Simpler migrations — one schema, all tenants
- No per-tenant migration runner needed
- Sufficient isolation for Pro and Enterprise tiers at MVP scale
- Admin cross-tenant reporting is straightforward

## Migration Trigger to Schema-Per-Tenant

Re-evaluate if an Enterprise client contractually requires
data schema isolation (e.g. government, healthcare adjacent projects).
Ash supports context strategy — the switch is possible but costly.

## Consequences

- organization_id must be present in every Oban job arg

# pass tenant to every Ash call

process boundary (HTTP request, Channel message, Oban job)

- Tigris storage paths must be org-prefixed for logical isolation
- Forgetting to set tenant = data leakage bug — enforce in code review
