-- SEE console link (公司环境管理平台): one optional URL per Environment pointing to where the
-- environment is configured/deployed. Explicit field, not a generic tag (may become a typed
-- links list if more external systems appear).
ALTER TABLE environment ADD (see_url VARCHAR2(500));
