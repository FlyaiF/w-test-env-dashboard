-- Resource Inventory: shared Server and Database aggregates (ADR-0003). They have independent
-- lifecycle and are referenced by Components by ID, never owned by an Environment.
-- Secrets are NOT modeled here (slice 06) — only non-secret connection metadata.
--
-- Lifecycle rules (AC3):
--   * Deleting an Environment cascades to its Components and their use-links, but never touches
--     a Server/Database row.
--   * Deleting a Server/Database that is still referenced is blocked (FK with no cascade);
--     the service surfaces this as 409 rather than letting it silently cascade.

CREATE SEQUENCE server_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE database_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE server (
    id            NUMBER(19)     NOT NULL,
    host          VARCHAR2(255)  NOT NULL,
    os            VARCHAR2(20)   NOT NULL,   -- ServerOs: LINUX | WINDOWS
    ssh_host      VARCHAR2(255),
    ssh_port      NUMBER(10),
    ssh_username  VARCHAR2(200),
    CONSTRAINT pk_server PRIMARY KEY (id)
);

-- "database" is a reserved word; the table is database_resource, the aggregate is Database.
CREATE TABLE database_resource (
    id                 NUMBER(19)     NOT NULL,
    role               VARCHAR2(100),
    db_type            VARCHAR2(40)   NOT NULL,   -- DatabaseType: ORACLE | DAMENG | OCEANBASE | OTHER
    conn_host          VARCHAR2(255),
    conn_port          NUMBER(10),
    conn_service_name  VARCHAR2(200),
    conn_username      VARCHAR2(200),
    CONSTRAINT pk_database PRIMARY KEY (id)
);

-- A Component runs-on one Server (by ID). RESTRICT (no cascade): a referenced Server cannot be deleted.
ALTER TABLE component ADD (server_id NUMBER(19));
ALTER TABLE component ADD CONSTRAINT fk_component_server
    FOREIGN KEY (server_id) REFERENCES server (id);
CREATE INDEX ix_component_server ON component (server_id);

-- A Component uses 0..N Databases (by ID). Deleting the Component drops its links (CASCADE);
-- deleting a still-used Database is blocked (no cascade on fk_compdb_database).
CREATE TABLE component_database (
    component_id  NUMBER(19)  NOT NULL,
    database_id   NUMBER(19)  NOT NULL,
    CONSTRAINT pk_component_database PRIMARY KEY (component_id, database_id),
    CONSTRAINT fk_compdb_component FOREIGN KEY (component_id)
        REFERENCES component (id) ON DELETE CASCADE,
    CONSTRAINT fk_compdb_database FOREIGN KEY (database_id)
        REFERENCES database_resource (id)
);
CREATE INDEX ix_compdb_database ON component_database (database_id);
