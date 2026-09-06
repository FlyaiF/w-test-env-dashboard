# Plan — Slice 01: Walking skeleton, read Environments (backend)

> Status: archived
> Scope: original redesign implementation slice
> Archived: 2026-09-06

Historical handoff evidence only. Status and test results below describe the original work,
not verification performed during documentation cleanup. Current sources: [documentation index](../../../../README.md).

Implements [issues/01-walking-skeleton-read-environments.md](../issues/01-walking-skeleton-read-environments.md).
Scope: a Spring Boot backend in this monorepo that boots, owns a greenfield normalized schema for the
`Environment` + `Component` aggregate, and serves the read path. No `Server`/`Database` refs (slice 04),
no Collection writeback (slice 05), no write path (slice 03).

## 1. Stack & layout decisions

| Decision | Choice | Why |
|---|---|---|
| Build tool | **Maven** | Maintainer already thinks in Maven coordinates; declarative, Spring Boot default works fine |
| Java | **21 (LTS)** | Spring Boot 3.x needs 17+; 21 is current LTS |
| Framework | **Spring Boot 3.3.x** (web, data-jpa, validation, actuator) | |
| Migrations | **Flyway** | Versioned SQL that runs identically on H2 and Oracle |
| Local DB | **H2 in Oracle compatibility mode** (`;MODE=Oracle`) | Shrinks dialect drift vs. the real Oracle 11g target |
| Prod DB | **Oracle 11g** via `com.oracle.database.jdbc:ojdbc8:19.21.0.0` | Settled |
| Module dir | **`backend/`** (new top-level, alongside `apps/`, `go_sidecar/`, `zipr/`) | Monorepo decision |

**To confirm before kickoff:** Java base package / Maven groupId. Plan assumes
`com.flyaif.envdashboard` (group `com.flyaif`, artifact `env-dashboard-backend`) — swap if you have a
house convention.

## 2. Package structure (package-by-context, deep modules)

```
backend/
├── pom.xml
└── src/
    ├── main/
    │   ├── java/com/flyaif/envdashboard/
    │   │   ├── EnvDashboardApplication.java
    │   │   └── catalog/                         # Environment Catalog bounded context
    │   │       ├── domain/
    │   │       │   ├── Environment.java          # aggregate root, owns components
    │   │       │   ├── Component.java
    │   │       │   ├── ComponentRole.java        # gateway | ui | app | private_proto | …
    │   │       │   ├── CollectionStatus.java     # ok | failed | unsupported (nullable until slice 05)
    │   │       │   └── VersionProbeKind.java     # db | ssh_file | command | http | none (nullable until 05)
    │   │       ├── EnvironmentRepository.java     # Spring Data JPA
    │   │       ├── EnvironmentService.java        # read use-cases (list, getById)
    │   │       └── web/
    │   │           ├── EnvironmentController.java # thin; GET /api/environments[/{id}]
    │   │           ├── dto/EnvironmentDto.java, ComponentDto.java
    │   │           └── EnvironmentMapper.java     # domain → DTO (published contract)
    │   └── resources/
    │       ├── application.yml                    # shared (Flyway on, actuator health)
    │       ├── application-local.yml              # H2 Oracle-mode, seed loader on
    │       ├── application-prod.yml               # Oracle 11g datasource (creds via env)
    │       └── db/migration/V1__catalog_schema.sql
    └── test/java/com/flyaif/envdashboard/catalog/
        ├── EnvironmentControllerTest.java         # @SpringBootTest + MockMvc, H2
        └── EnvironmentRepositoryTest.java         # @DataJpaTest, H2
```

The controller stays thin; `Environment`/`Component` hold the model. DTOs are the *server's published
contract* — the client builds its own anti-corruption layer over them in slice 02.

## 3. Schema — `V1__catalog_schema.sql`

Two tables. Portable SQL that runs on H2(Oracle-mode) and Oracle 11g.

```
environment
  id           NUMBER(19)    PK
  name         VARCHAR2(200) NOT NULL
  memo         VARCHAR2(1000) NULL

component
  id                 NUMBER(19)    PK
  environment_id     NUMBER(19)    NOT NULL  FK → environment(id) ON DELETE CASCADE
  role               VARCHAR2(40)  NOT NULL            -- ComponentRole
  app_version        VARCHAR2(200) NULL                -- the live Version, or blank
  deploy_time        TIMESTAMP     NULL
  log_location       VARCHAR2(500) NULL
  listen_port        NUMBER(10)    NULL
  protocol           VARCHAR2(40)  NULL
  url                VARCHAR2(500) NULL
  version_probe      VARCHAR2(40)  NULL                -- VersionProbeKind (set in slice 05)
  collection_status  VARCHAR2(20)  NULL                -- CollectionStatus  (set in slice 05)
  last_collected_at  TIMESTAMP     NULL
```

**Oracle 11g gotchas baked in:**
- **No IDENTITY columns** (12c+ only). Use `GenerationType.SEQUENCE` with explicit `CREATE SEQUENCE`
  per table (`environment_seq`, `component_seq`) — works on both H2 and 11g. Do **not** use `IDENTITY`.
- **No native BOOLEAN** — none modeled here; keep enums as VARCHAR.
- **Timestamps as `TIMESTAMP`**, not `DATE`, to dodge the legacy "Oracle DATE has no tz" trap
  (AGENTS.md). Persist instants; the client still calls `.toLocal()` before formatting.
- `ON DELETE CASCADE` on the FK declares the slice-03 cascade boundary now, even though the write path
  lands later.

Enums stored as strings (`@Enumerated(EnumType.STRING)`) so a bad/new value is legible, not an ordinal.

## 4. API contract

- `GET /api/environments` → `200` `[ EnvironmentDto, … ]`, each with its `components: [ComponentDto]`.
- `GET /api/environments/{id}` → `200` `EnvironmentDto`; `404` (problem+json) for unknown id.
- `GET /actuator/health` → liveness (satisfies the health-check AC; custom `/health` alias optional).

`EnvironmentDto { id, name, memo, components[] }`
`ComponentDto { id, role, version, deployTime, logLocation, listenPort, protocol, url, versionProbe,
collectionStatus, lastCollectedAt }` — `version` maps the `app_version` column; collection fields are
present but null until slice 05. JSON is camelCase; field names follow the glossary (no `e_*`, no
`webserver`).

## 5. Seed data (for the demoability AC)

Local-profile-only `CommandLineRunner` (`@Profile("local")`) that inserts ~2 Environments with a few
Components if the table is empty. Keeps prod migrations clean (no seed rows ship to Oracle).

## 6. Test strategy

- **Default (fast, every run):** H2 in Oracle mode. `EnvironmentRepositoryTest` (`@DataJpaTest`) covers
  persistence + the owns-Components mapping; `EnvironmentControllerTest` (`@SpringBootTest` + MockMvc)
  covers both endpoints incl. the `404`. Flyway runs against H2 so migrations are exercised.
- **Optional (Oracle-dialect validation):** a Testcontainers profile using `gvenzl/oracle-xe:11-slim`
  (a real 11g) to prove `V1` + the sequences run on Oracle. Tag it so it's skippable in dev but
  available in CI. Recommend including it — it's the only thing that actually de-risks the 11g target.

## 7. CI

Add a `backend` job to `.github/workflows/build.yml`: `mvn -f backend/pom.xml verify` (JDK 21). Gate the
Testcontainers Oracle test behind a label or a separate job so PRs aren't always paying the image pull.

## 8. Build & run

```
cd backend && mvn spring-boot:run -Dspring-boot.run.profiles=local   # H2 + seed
curl localhost:8080/api/environments
curl localhost:8080/actuator/health
```

Add a `scripts/dev_backend.sh` mirroring the existing `dev_*.sh` helpers.

## 9. Step order (suggested commits)

1. `backend/` Maven module + `EnvDashboardApplication` + actuator health — boots, green.
2. `V1` migration + sequences; `Environment`/`Component` entities + enums; repository; `@DataJpaTest`.
3. Service + controller + DTOs + mapper; `GET` list & by-id; MockMvc tests incl. 404.
4. Local seed loader; manual curl check.
5. Testcontainers Oracle-XE 11 dialect test (optional but recommended).
6. CI job + `scripts/dev_backend.sh`.

## 10. Out of scope (explicit, to avoid scope creep)

No `Server`/`Database` tables or FKs (slice 04). No POST/PUT/DELETE (slice 03). No collector,
scheduler, or probe code — the collection columns exist but stay null (slice 05). No auth/WebSocket
seams beyond what Spring Boot gives for free. No client changes (slice 02).
```
