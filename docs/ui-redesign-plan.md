# env_viewer UI/Internal Rework — Handoff Plan

Status: **decisions locked, ready to implement** (2026-07-29).
Decided interactively with the user via design grilling + visual prototypes; do not re-litigate the
locked decisions below. The approved visual prototype is
[`docs/prototypes/ui-redesign-visual-directions.html`](prototypes/ui-redesign-visual-directions.html)
(open in a browser; **方向 D 组合方案 is the approved design**, A/B/C are rejected references; ←/→
switches variants, 🌓 toggles light/dark). Published copy:
https://claude.ai/code/artifact/2d42b168-cc8a-4cf2-8b2c-813bed58b053

## Locked decisions

1. **Core job**: ops glance-and-launch — find an environment fast, read health/staleness at a
   glance, launch SSH/DB tools in 1–2 clicks. Curation/CRUD stays but is secondary.
2. **Catalog shape**: keep master-detail. Left roster = scannable rows (health dot, name,
   `#id · N组件 · 相对时间`, ⚠ staleness flag). Right detail = compact **grid-aligned** component
   rows, expandable per-row to full fields + credentials.
3. **Health rollup** (new, derived client-side in `catalog_acl.dart` — no API needed):
   env status = worst-of component `collectionStatus` **excluding UNSUPPORTED** components
   (they render a neutral chip and don't count). Any FAILED → ✗ 异常; else any PENDING/未采集 → ○
   待采集; else ● 正常. **Staleness**: ⚠ when the newest `lastCollectedAt` across collectable
   components is > 24h old (fixed constant, no setting).
4. **Inventory shape**: replace card grids with one dense sortable table per tab (服务器 / 数据库).
   服务器 columns: ID, 主机, 操作系统, SSH 地址, 密码(已设置/未设置), 引用, actions.
   数据库 columns: ID, 用途, 类型, 连接, 用户名, 密码, 引用, actions.
   The 引用 count itself is the clickable affordance opening the usage view (replaces the hidden
   `查看使用情况` icon → dialog flow); no separate 用途 button.
5. **Visual identity = prototype 方向 D**: warm-graphite console ground, ALL machine data
   (versions, hosts, ports, addresses, timestamps) in **Sarasa Mono SC** aligned columns, UI text in
   Sarasa Gothic SC; color used ONLY for meaning (one teal accent for interaction/selection, strict
   green/amber/red status language); soft rounded selection fills (no left-edge bars); operations
   compressed to uniform icon buttons with tooltips. Light and dark are both first-class.
6. **Operations display**: row-end fixed icon action column. Component rows: `>_` (SSH 连接) and
   `⛁` (数据库工具) — in Flutter use Material icons (e.g. `Icons.terminal`, `Icons.storage`) at one
   fixed size in uniform `IconButton`s; placeholder keeps column alignment when a component has no
   databases; actions dimmed (~60% opacity) until row hover. Detail-header actions: ◉ 采集 (compact
   label), edit/delete as icon buttons with tooltips. Primary per-page action (＋ 新建环境 / ＋ 新建服务器)
   keeps its full label. All icon buttons identical height; the prototype's size mismatch feedback
   means: **uniform icon size + uniform button height everywhere**.
7. **Naming**: standardize on **环境目录 / 资源清单** everywhere — sidebar nav, page headers,
   dialogs, messages. (Kills 总览 and 资源库存.)
8. **Sidebar**: stays expanded by default; manual collapse toggle persisted in `~/.test-env-dashboard/ui.json`;
   **remove** the auto-collapse-on-navigate behavior (`didUpdateWidget` in
   `packages/shared_ui/lib/src/app_scaffold.dart` forcing `_expanded = false`).
9. **Scope**: full internal cleanup (items a–f in the phases below). Do NOT touch: credential
   broker, collection engine/probes, legacy import, zipr_tool, go_sidecar.

## Design tokens (from approved 方向 D)

Fonts: UI = Sarasa Gothic SC; data = Sarasa Mono SC (already shipped). Radii: controls 6, list rows
9, cards 8, chips 4. Component-row grid columns: dot | role(~92) | version(~134) | updated(~128) |
host(flex) | status chip(~72) | actions(fixed) | chevron. Button heights uniform (toolbar 27px-ish,
row actions slightly smaller — exact Flutter sizes may adapt, uniformity is the requirement).

| Token | Light | Dark |
|---|---|---|
| bg | `#F4F4F1` | `#17181A` |
| sidebar bg | `#ECECE8` | `#131416` |
| roster bg | `#F0F0EC` | `#151618` |
| card bg | `#FBFBF9` | `#1E2023` |
| card body bg | `#F6F6F3` | `#1A1C1E` |
| table header bg | `#F1F1ED` | `#1B1D20` |
| text | `#26282A` | `#DCDEE0` |
| text secondary | `#71757A` | `#8B9095` |
| border | `#D3D3CC` | `#303337` |
| border soft | `#E2E2DB` | `#26292C` |
| card border | `#DBDBD4` | `#2C2F33` |
| hover | `#E9E9E4` | `#232528` |
| selection bg | `#DBEAE8` | `#20312F` |
| selection border | `#C4DBD8` | `#2E4A47` |
| accent (teal) | `#1F7A76` | `#59B3AD` |
| on-accent | `#FFFFFF` | `#10201F` |
| ok | `#2E7D4F` | `#5CB380` |
| ok bg | `#E4EFE7` | `#1D2B22` |
| warn (staleness) | `#A56D0A` | `#D2A24A` |
| err | `#B4402C` | `#DF6E58` |
| err bg | `#F5E4E0` | `#33211D` |
| neutral chip bg | `#EAEAE5` | `#232528` |

## Implementation phases

### Phase 1 — shared_ui foundation (item a)
- Replace the 17-line `packages/shared_ui/lib/src/theme.dart` with a token-based theme: a
  `ThemeExtension` (or equivalent) carrying the table above + spacing/radius scale + status colors,
  building both light/dark `ThemeData` (keep `ColorScheme` aligned with the accent). Remove
  hardcoded `Colors.green/red` in `app_scaffold.dart` and `catalog_page.dart`.
- New shared primitives in `shared_ui` (replacing per-page private duplicates): `StatusChip`
  (ok/err/none/na), `IdBadge`, `ErrorBanner` (+重试), `EmptyState`, `LabelValueRow`, `PageHeader`
  (title + `显示 N / M 条` + search + primary action + refresh, with the existing <900px reflow).
- `AppScaffold`: soft rounded selection style per tokens (no left border bar), remove
  auto-collapse-on-navigate, persist expanded state via `AppThemeController`-style ui.json config.
- Declare fonts properly or keep the current per-app declaration, but remove the silent
  `'Sarasa Mono SC'` hardcode in `about_section.dart` in favor of a theme token.

### Phase 2 — backend additive changes (items c, f)
- `referenceCount` on server/database **list** DTOs (grouped count over component links —
  inventory module `backend/src/main/java/com/flyaif/envdashboard/inventory/`).
- Persist probe failure detail: `ProbeResult.detail` exists
  (`collection/probe/ProbeResult.java`) but `CollectionService.apply()` drops it. Add nullable
  `collection_detail` column (new Flyway migration in `backend/src/main/resources/db/migration/`),
  set it in `apply()` (null on OK), expose as `collectionDetail` in `ComponentDto`.
- `mvn -f backend/pom.xml verify`.

### Phase 3 — catalog page rebuild (item b + design)
- `apps/env_viewer/lib/catalog/catalog_acl.dart` + `environment_view.dart`: derive
  `EnvironmentHealth` (rollup enum + newest collect instant + `isStale`) per decision 3; map
  `collectionDetail`.
- Rebuild `apps/env_viewer/lib/pages/catalog/catalog_page.dart` per prototype D: roster rows,
  grid-aligned expandable component rows (collapsed: dot/role/version/updated/host/chip/actions;
  expanded: field grid + SSH 信息 + 数据库信息 credential sections + failure reason line
  `采集失败：<detail>` in err color), icon actions with tooltips. Fix the loading-indicator layout
  shift (reserve the space or overlay). Keep selection stable under filtering where possible.

### Phase 4 — inventory page rebuild (item d + design)
- Rebuild `apps/env_viewer/lib/pages/inventory/inventory_page.dart` as sortable tables (client-side
  sort is fine), 引用 column from `referenceCount` opening the usage view, actions column (edit ✎ /
  delete ✕ icons, tooltips).
- Unify search: `FilterHistoryTextField` + 250ms debounce on both pages; move inventory filtering
  into `InventoryStore` (like the catalog) and stop clearing the query on tab switch.

### Phase 5 — settings/about polish + naming pass (item e)
- Settings: persist feedback (e.g. `已保存` inline/snackbar), expose the existing
  `ThemeModeSelector` from `theme_mode_controller.dart` (currently only zipr_tool renders it).
- Naming pass: 环境目录 / 资源清单 in `apps/env_viewer/lib/widgets/app_scaffold.dart` nav labels and
  everywhere else (总览/资源库存 die).

### Phase 6 — verify
- `cd apps/env_viewer && flutter analyze && flutter test` — **unset proxy vars first**
  (`unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy`).
- `mvn -f backend/pom.xml verify`.
- Run `./scripts/sync_assets.sh` once; backend via `./scripts/dev_backend.sh run`, client via
  `./scripts/dev_env_viewer.sh run`. Real imported H2 data exists at
  `~/.test-env-dashboard/h2/envdashboard` (run backend with `SPRING_DATASOURCE_URL` override) for a
  realistic visual check in both light and dark.

## Notes
- Work happens on branch `design/env-dashboard-redesign`.
- Oracle `DATE` gotcha: keep calling `.toLocal()` before display.
- The prototype HTML is throwaway design source, not production code; do not port its CSS literally
  — port its tokens and layout intent into the Flutter theme/widgets.
