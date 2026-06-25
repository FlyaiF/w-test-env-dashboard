# 07 — One-time TENVINFO import script

Status: ready-for-agent

## Parent

[docs/PRD-redesign.md](../../../docs/PRD-redesign.md) — Test Environment Dashboard Redesign.

## What to build

A one-time scripted migration (ADR-0004, PRD §8) that reads the legacy `TENVINFO` table and writes the
new normalized schema. It parses the composite strings and fixed slots into proper rows:
`E_WEBSERVERADDR` = `"host:port&user/password"` splits into a `Server`/`Component` reachability plus
brokered credentials; the two fixed DB slots become `Database` references. The import doubles as proof
the new model can represent reality.

It must **surface, never silently drop**, rows it cannot parse — dirty composite strings, missing
creds, ambiguous DB roles (PRD §9) — emitting a report of skipped/ambiguous rows for human follow-up.
This is run-once tooling, executed after the new schema (slices 01 + 04) is ready and before cutover.

## Acceptance criteria

- [ ] Script reads `TENVINFO` and populates Environment / Component / Server / Database rows in the new schema
- [ ] `E_WEBSERVERADDR` composite strings and the fixed DB slots are parsed into proper normalized rows
- [ ] Unparseable / ambiguous / incomplete rows are reported, not silently dropped
- [ ] The script is idempotent or safely re-runnable against a fresh target schema
- [ ] A dry-run / report mode lists what would be imported and what would be skipped, with reasons

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
- 04 — Resource Inventory (import needs the Server/Database schema)
