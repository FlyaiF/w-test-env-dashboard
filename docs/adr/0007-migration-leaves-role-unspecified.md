# The TENVINFO migration leaves a migrated Component's role UNSPECIFIED, never guessed

The legacy `TENVINFO` row captures exactly one "web server" per Environment and carries **no role
discriminator** — nothing distinguishes a gateway from a UI from a main service. Issue 07's settled
migration policy is "dirty/ambiguous fields are left blank, never invented," so stamping any concrete
`ComponentRole` (the old `GATEWAY`, or a plausible `APP`) would be an invention. We therefore added an
explicit `ComponentRole.UNSPECIFIED` (rendered `未指定`) and the migration assigns it, recording the
absence of a role honestly for a human to classify later. This is a deliberate deviation from the
obvious "pick a sensible default" — recorded so a future engineer doesn't "fix" it into a wrong guess.

## Consequences

- `role` stays `NOT NULL`; `UNSPECIFIED` is the sentinel, so no schema/nullability change is needed
  (the column is a string).
- `未指定` is a real, selectable role in the client: it leads the role dropdown and is the default for
  a hand-added Component, forcing a conscious classification. It also supersedes the client's former
  implicit `null → 未知组件` placeholder (one term for "no role assigned").
