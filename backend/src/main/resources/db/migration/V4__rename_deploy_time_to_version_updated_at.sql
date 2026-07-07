-- The collected timestamp is the Version update time (版本更新时间): when the environment's business
-- DB last had a schema change applied — not an app deploy time (see CONTEXT.md, issue 08).
ALTER TABLE component RENAME COLUMN deploy_time TO version_updated_at;
