-- Access Brokering (ADR-0005, slice 06): secret material for shared Servers and Databases, stored
-- ENCRYPTED at rest (never plaintext). Kept in their own tables, owned by the Access Brokering
-- context, so the Resource Inventory read path provably cannot leak a secret — the inventory DTOs
-- have no secret column to populate.
--
-- Each row holds the at-rest ciphertext (Base64 of IV || ciphertext+tag, produced by SecretCipher).
-- One secret per resource (PK = resource id). ON DELETE CASCADE: deleting a Server/Database drops
-- its secret with it (deletion itself is still blocked while the resource is referenced — V2).

CREATE TABLE server_secret (
    server_id   NUMBER(19)     NOT NULL,
    secret_enc  VARCHAR2(2000) NOT NULL,
    CONSTRAINT pk_server_secret PRIMARY KEY (server_id),
    CONSTRAINT fk_server_secret_server FOREIGN KEY (server_id)
        REFERENCES server (id) ON DELETE CASCADE
);

CREATE TABLE database_secret (
    database_id  NUMBER(19)     NOT NULL,
    secret_enc   VARCHAR2(2000) NOT NULL,
    CONSTRAINT pk_database_secret PRIMARY KEY (database_id),
    CONSTRAINT fk_database_secret_database FOREIGN KEY (database_id)
        REFERENCES database_resource (id) ON DELETE CASCADE
);
