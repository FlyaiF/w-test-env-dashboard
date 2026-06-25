# 01 — Walking skeleton: read Environments (backend)

Status: ready-for-agent

## Parent

[docs/PRD-redesign.md](../../../docs/PRD-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Stand up the new Spring Boot / Java backend (ADR-0002) as a walking skeleton that proves the
client-server architecture end-to-end on the read path. The backend boots, owns a fresh **normalized
schema** for the `Environment` aggregate root and its `Component`s (ADR-0004 — greenfield, `TENVINFO`
is not involved), and serves them over an HTTP API.

A `Component` carries: role, a single `Version` (or blank) + deploy time, log location, reachability
(listen port / protocol / URL), and collection status + last-collected time as nullable fields (not
yet populated — that is slice 05). `Server`/`Database` references are out of scope here (slice 04).

Endpoints:

- `GET /api/environments` — list Environments with their Components.
- `GET /api/environments/{id}` — one Environment with its Components.

JVM mode is the default; do not let GraalVM native-image concerns block the build (ADR-0002).

## Acceptance criteria

- [ ] Spring Boot backend boots locally and serves a `GET /health` (or equivalent) check
- [ ] Normalized schema (migrations) exists for `Environment` and `Component` with the fields above; `TENVINFO` is not referenced
- [ ] `GET /api/environments` returns seeded Environments each with their Components
- [ ] `GET /api/environments/{id}` returns a single Environment with its Components, and 404s for an unknown id
- [ ] Integration tests cover both endpoints against a real (or testcontainer) database
- [ ] API field names use glossary vocabulary (Environment, Component, Version, deploy time) — not legacy terms

## Blocked by

None — can start immediately.
