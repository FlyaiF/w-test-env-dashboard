-- Environment Catalog: greenfield normalized schema (ADR-0004; TENVINFO retired).
-- Portable SQL that runs on H2 (Oracle compatibility mode) and Oracle 11g.
--
-- Oracle 11g gotchas baked in:
--   * No IDENTITY columns (12c+ only) -> explicit sequences + JPA SEQUENCE generation.
--   * No native BOOLEAN -> enums stored as VARCHAR2 strings.
--   * TIMESTAMP (not DATE) to dodge the legacy "Oracle DATE has no tz" trap.

CREATE SEQUENCE environment_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE component_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE environment (
    id    NUMBER(19)     NOT NULL,
    name  VARCHAR2(200)  NOT NULL,
    memo  VARCHAR2(1000),
    CONSTRAINT pk_environment PRIMARY KEY (id)
);

CREATE TABLE component (
    id                 NUMBER(19)     NOT NULL,
    environment_id     NUMBER(19)     NOT NULL,
    role               VARCHAR2(40)   NOT NULL,   -- ComponentRole
    app_version        VARCHAR2(200),             -- live Version, or blank
    deploy_time        TIMESTAMP,
    log_location       VARCHAR2(500),
    listen_port        NUMBER(10),
    protocol           VARCHAR2(40),
    url                VARCHAR2(500),
    version_probe      VARCHAR2(40),              -- VersionProbeKind (populated in slice 05)
    collection_status  VARCHAR2(20),              -- CollectionStatus  (populated in slice 05)
    last_collected_at  TIMESTAMP,
    CONSTRAINT pk_component PRIMARY KEY (id),
    CONSTRAINT fk_component_environment
        FOREIGN KEY (environment_id) REFERENCES environment (id) ON DELETE CASCADE
);

CREATE INDEX ix_component_environment ON component (environment_id);
