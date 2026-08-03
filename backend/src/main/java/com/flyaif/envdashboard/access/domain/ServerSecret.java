package com.flyaif.envdashboard.access.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * The encrypted SSH secret (password or key passphrase) for a {@code Server}, keyed by the Server's
 * id. {@code secretEnc} is always ciphertext at rest (ADR-0005) — the plaintext only exists transiently
 * while {@link com.flyaif.envdashboard.access.SecretStore} encrypts on write or decrypts for delivery.
 */
@Entity
@Table(name = "server_secret")
public class ServerSecret {

    @Id
    @Column(name = "server_id")
    private Long serverId;

    @Column(name = "secret_enc", nullable = false, length = 2000)
    private String secretEnc;

    protected ServerSecret() {
        // for JPA
    }

    public ServerSecret(Long serverId, String secretEnc) {
        this.serverId = serverId;
        this.secretEnc = secretEnc;
    }

    public Long getServerId() {
        return serverId;
    }

    public String getSecretEnc() {
        return secretEnc;
    }

    public void setSecretEnc(String secretEnc) {
        this.secretEnc = secretEnc;
    }
}
