# Context Map

> Status: current
> Scope: env_viewer and backend
> Reviewed: 2026-09-06 (code structure)

Shared vocabulary lives in [CONTEXT.md](CONTEXT.md). This map describes current responsibilities;
`zipr_tool` is a separate product, described in its [README](apps/zipr_tool/README.md).
No per-context glossary is required until a distinct vocabulary needs one.

## Contexts and code locations

| Context | Responsibility | Code |
| --- | --- | --- |
| Environment Catalog | Owns Environments and their Components; curation and resource links | [backend catalog](backend/src/main/java/com/flyaif/envdashboard/catalog) |
| Resource Inventory | Shared Server / Database lifecycle, connection metadata and usage checks | [backend inventory](backend/src/main/java/com/flyaif/envdashboard/inventory) |
| Version Collection | Scheduled/manual collection, probes, Version update time and collection status | [backend collection](backend/src/main/java/com/flyaif/envdashboard/collection) |
| Access Brokering | Encrypted secret storage and on-demand credential delivery | [backend access](backend/src/main/java/com/flyaif/envdashboard/access) |
| Local Desktop Integration | External tool launch and direct read-only SSH/SFTP file sessions | [access](apps/env_viewer/lib/services/access), [remote file sessions](apps/env_viewer/lib/services/remote_file) |
| Presentation | DTO-to-view mappings, UI state and navigation | [catalog](apps/env_viewer/lib/catalog), [inventory](apps/env_viewer/lib/inventory), [remote files](apps/env_viewer/lib/remote_files), [pages](apps/env_viewer/lib/pages) |

Supporting technical modules: [legacy import](backend/src/main/java/com/flyaif/envdashboard/legacyimport),
[client update distribution](backend/src/main/java/com/flyaif/envdashboard/clientupdate),
[desktop update flow](apps/env_viewer/lib/services/update), and the independent
[updater helper](apps/env_viewer/updater). These are code responsibilities, not additional business glossaries.

## Relationships

- **Environment Catalog → Resource Inventory**: Components reference Server / Database IDs;
  the Catalog never owns those resources. Inventory checks usage through its `ResourceUsage`
  interface, implemented by Catalog's `CatalogResourceUsage` adapter.
- **Version Collection → Environment Catalog**: reads what to probe and writes Version,
  Version update time, last-collected time, status and failure detail back to Components.
- **Version Collection → Machine Access**: probes obtain remote data through the backend's
  machine-access module; this is separate from the desktop's interactive file sessions.
- **Access Brokering → Resource Inventory**: secrets attach to Server / Database resources.
- **Presentation → backend**: catalog and inventory data are canonical on the backend;
  client ACL mappings resolve references into display models ([ADR-0006](docs/adr/0006-read-models-over-cqrs.md)).
- **Access Brokering → Local Desktop Integration**: on-demand credentials support tool launching,
  explicit reveal/copy and SSH/SFTP sessions; the desktop never stores secrets durably.
- **Local Desktop Integration → Server**: read-only file sessions connect directly from the desktop;
  the backend does not relay log streams ([ADR-0009](docs/adr/0009-client-side-read-only-remote-files.md)).

## Deferred scope

A future web client, RBAC and server-held log streaming are not current capabilities. Earlier plans
mention possible integration seams; this map does not claim those endpoints are implemented.
