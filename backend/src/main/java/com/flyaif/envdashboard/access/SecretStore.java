package com.flyaif.envdashboard.access;

import com.flyaif.envdashboard.access.domain.DatabaseSecret;
import com.flyaif.envdashboard.access.domain.ServerSecret;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

/**
 * The single gate between plaintext secrets and their at-rest ciphertext (ADR-0005). Everything in
 * persistence is encrypted; plaintext only crosses this boundary — encrypted on the way in, decrypted
 * on the way out. {@link AccessBrokerService} uses it to store and to broker, and Version Collection
 * uses {@link #databaseSecret} to authenticate its probe connections.
 *
 * <p>Stores are upserts (one secret per resource id). Callers are responsible for checking that the
 * resource exists first, so a 404 is surfaced rather than an FK violation.
 */
@Service
@Transactional
public class SecretStore {

    private final ServerSecretRepository serverSecrets;
    private final DatabaseSecretRepository databaseSecrets;
    private final SecretCipher cipher;

    public SecretStore(ServerSecretRepository serverSecrets,
                       DatabaseSecretRepository databaseSecrets,
                       SecretCipher cipher) {
        this.serverSecrets = serverSecrets;
        this.databaseSecrets = databaseSecrets;
        this.cipher = cipher;
    }

    public void putServerSecret(Long serverId, String plaintext) {
        String encrypted = cipher.encrypt(plaintext);
        ServerSecret row = serverSecrets.findById(serverId)
                .map(existing -> {
                    existing.setSecretEnc(encrypted);
                    return existing;
                })
                .orElseGet(() -> new ServerSecret(serverId, encrypted));
        serverSecrets.save(row);
    }

    public void putDatabaseSecret(Long databaseId, String plaintext) {
        String encrypted = cipher.encrypt(plaintext);
        DatabaseSecret row = databaseSecrets.findById(databaseId)
                .map(existing -> {
                    existing.setSecretEnc(encrypted);
                    return existing;
                })
                .orElseGet(() -> new DatabaseSecret(databaseId, encrypted));
        databaseSecrets.save(row);
    }

    @Transactional(readOnly = true)
    public Optional<String> serverSecret(Long serverId) {
        return serverSecrets.findById(serverId).map(s -> cipher.decrypt(s.getSecretEnc()));
    }

    @Transactional(readOnly = true)
    public Optional<String> databaseSecret(Long databaseId) {
        return databaseSecrets.findById(databaseId).map(s -> cipher.decrypt(s.getSecretEnc()));
    }
}
