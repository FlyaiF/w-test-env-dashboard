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

**Settled policy for messy data:** when a field is dirty but the row is otherwise usable, **leave that
field blank** and carry on (fix later by hand). When a row simply **cannot fit the new shape**, **drop
it and log it** in the migration report — never silently discard. Either way the run emits a report of
every blanked field and dropped row, with the reason, for human follow-up. This is run-once tooling,
executed after the new schema (slices 01 + 04) is ready and before cutover.

## Acceptance criteria

- [ ] Script reads `TENVINFO` and populates Environment / Component / Server / Database rows in the new schema
- [ ] `E_WEBSERVERADDR` composite strings and the fixed DB slots are parsed into proper normalized rows
- [ ] Dirty-but-usable fields are left blank (not invented); rows that cannot fit the new shape are dropped and logged — never silently discarded
- [ ] Unparseable / ambiguous / incomplete rows are reported with reasons
- [ ] The script is idempotent or safely re-runnable against a fresh target schema
- [ ] A dry-run / report mode lists what would be imported and what would be skipped, with reasons

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
- 04 — Resource Inventory (import needs the Server/Database schema)
