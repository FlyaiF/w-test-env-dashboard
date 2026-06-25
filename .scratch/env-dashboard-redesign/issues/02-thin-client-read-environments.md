# 02 — Thin client reads Environments from the backend

Status: ready-for-agent

## Parent

[docs/PRD-redesign.md](../../../docs/PRD-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Slim the `env_viewer` Flutter app down to a thin client (ADR-0001, ADR-0005) that reads its data from
the new backend instead of owning it. Shed the local-tool machinery: Go sidecar spawning and IPC, the
local JSON canonical store at `~/.test-env-dashboard/config.json`, sync/merge, and **all** direct
Oracle/DB access (no DB drivers ship to the desktop).

In their place, add a backend HTTP client and an **anti-corruption layer** that translates backend API
DTOs into the client's view models, so backend shapes never leak into the UI. Render the Environment
list and Environment detail (its Components) read-only against the live backend from slice 01.

The tool registry (launching the user's SSH/DB tools) stays in the app but is not wired to data yet
— that is slice 06.

## Acceptance criteria

- [ ] Sidecar spawning/IPC, the local JSON store, sync/merge, and all DB access are removed from `env_viewer`
- [ ] A backend API client fetches Environments from slice 01's endpoints
- [ ] An anti-corruption layer maps API DTOs to view models; UI code does not reference raw DTOs
- [ ] Environment list and Environment detail (Components) render read-only against a running backend
- [ ] `flutter analyze` is clean and `flutter test` passes (proxy env vars unset per AGENTS.md)
- [ ] UI strings remain Chinese; domain terms map to the glossary (no "web server"/"TENVINFO" leakage)

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
