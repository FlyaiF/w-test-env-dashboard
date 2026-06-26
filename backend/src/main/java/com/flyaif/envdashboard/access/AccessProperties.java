package com.flyaif.envdashboard.access;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration for the Access Brokering context (ADR-0005). The {@code secretKey} is the master
 * passphrase from which {@link SecretCipher} derives the AES key used to encrypt Server/Database
 * secrets at rest. It is supplied per environment (a fixed dev value locally, a high-entropy value
 * via an env var in prod) and is the one piece of material that must never be committed for prod.
 */
@ConfigurationProperties(prefix = "envdashboard.access")
public class AccessProperties {

    /** Master passphrase for secret encryption. Required; the cipher refuses a blank key. */
    private String secretKey;

    public String getSecretKey() {
        return secretKey;
    }

    public void setSecretKey(String secretKey) {
        this.secretKey = secretKey;
    }
}
