# Brokered credentials are populated by the TENVINFO migration and surfaced on demand in the client

> Status: accepted

The problem description below records the pre-decision behavior, not the current importer.
The reveal/copy constraints apply to those interactions; SSH file sessions may retain credentials
in memory for reconnect under [ADR-0009](0009-client-side-read-only-remote-files.md).

Slice 06 built Access Brokering (ADR-0005): Server/Database secrets live encrypted at rest and are
delivered to the client just-in-time, the client persisting nothing. Two gaps surfaced once the
redesign ran against real migrated data, and both pull against the original posture:

1. **The migration never populated the broker.** `TenvinfoImporter` parses the legacy password out of
   `E_WEBSERVERADDR` and the DB slots, bumps a `credentialSeen()` counter, redacts it from the report —
   and then **drops it**. The `SshAccess`/`ConnectionDescriptor` are built without it. This was an
   accident of sequencing (brokering, slice 06, landed after the importer, slice 07), not a recorded
   decision. Consequence: for every migrated environment the broker holds no secret, so any on-demand
   credential is empty.

2. **The client offered no way to read a credential**, only to launch a brokered tool. But users do
   connect by hand — `ssh` from their own terminal, `sqlplus`/PL/SQL Developer with a pasted
   connect-string — and the old TENVINFO UI showed the connection string (password included) as
   copyable text. The redesign removed that with nothing to replace it.

## Decision

- **The migration carries each parsed legacy password into the broker.** On a non-dry-run, after the
  Server/Database is saved, the importer calls `AccessBrokerService.storeServerSecret` /
  `storeDatabaseSecret` so the secret is encrypted at rest like any other. The legacy `TENVINFO`
  already holds these passwords in **plaintext**, so moving them into the encrypted store is strictly a
  security improvement, and it is the end state ADR-0005 already envisioned. The secret is stored only
  when the resource is first created; a password seen on a later row that dedupes onto an existing
  resource is noted in the report, not overwritten.

- **The client may reveal and copy a brokered credential on explicit demand.** This widens ADR-0005's
  delivery purpose from "launch a tool" to "launch a tool, or hand the user a credential they asked
  for." It does **not** weaken "the client persists nothing durable": every reveal/copy fetches from
  `GET /…/credentials` at click-time and caches nothing.
  - **SSH** gets an `SSH 信息` detail section (`user@host:port`) with the password **masked**, revealed
    or copied only by a deliberate per-credential action — so a glance at, or screenshot of, the
    catalog does not spray plaintext passwords.
  - **Database** gets a `数据库信息` section, one row per database, each with a 复制 action that
    assembles the full `username/password@host:port/serviceName` sqlplus connect-string at copy-time.
    Here the secret reaches the clipboard (an explicit act), never the screen.

## Consequences

- Re-running the importer is required to backfill secrets for data migrated before this change; the
  recommended path is a fresh target schema (the local-test recipe deletes the H2 file first).
- The catalog page makes one broker call per credential action (not on load); no secret is held in
  client state beyond the widget interaction that requested it.
- A resource with no stored secret (legacy row had none, or a parse miss) never produces an empty
  password. The SSH reveal/copy reports "未配置密码" and stays masked. The DB copy still yields a
  usable string — the connect-string builder drops the password segment entirely (`user@host…`,
  which prompts), never emitting a dangling `user/@host` — and the toast notes 无密码.
- This is deliberately a softening of "secrets never sit on the client UI." It is bounded: masked by
  default for SSH, clipboard-only (never rendered) for DB, always just-in-time, never persisted.
