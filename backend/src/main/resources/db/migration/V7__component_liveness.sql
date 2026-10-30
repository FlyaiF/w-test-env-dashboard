-- Running state (运行状态): whether a Component answers on its URL right now, checked by a frequent
-- backend sweep independent of Version Collection. Kept in its own columns so the two sweeps never
-- overwrite each other (the entity uses dynamic updates). All null until the first check, and
-- cleared again when a Component has no URL to check.
--   liveness             LivenessStatus: UP | DOWN | UNREACHABLE
--   liveness_changed_at  when the status last moved — "down since …"
ALTER TABLE component ADD (
    liveness             VARCHAR2(20),
    liveness_detail      VARCHAR2(500),
    liveness_checked_at  TIMESTAMP,
    liveness_changed_at  TIMESTAMP
);
