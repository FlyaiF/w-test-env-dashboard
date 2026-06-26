package com.flyaif.envdashboard.access.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * The encrypted login password for a {@code Database}, keyed by the Database's id. {@code secretEnc}
 * is always ciphertext at rest (ADR-0005); the plaintext only exists transiently inside
 * {@link com.flyaif.envdashboard.access.SecretStore} on write or delivery.
 */
@Entity
@Table(name = "database_secret")
public class DatabaseSecret {

    @Id
    @Column(name = "database_id")
    private Long databaseId;

    @Column(name = "secret_enc", nullable = false, length = 2000)
    private String secretEnc;

    protected DatabaseSecret() {
        // for JPA
    }

    public DatabaseSecret(Long databaseId, String secretEnc) {
        this.databaseId = databaseId;
        this.secretEnc = secretEnc;
    }

    public Long getDatabaseId() {
        return databaseId;
    }

    public String getSecretEnc() {
        return secretEnc;
    }

    public void setSecretEnc(String secretEnc) {
        this.secretEnc = secretEnc;
    }
}
