package com.flyaif.envdashboard.access;

import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * Symmetric encryption for secrets at rest (ADR-0005, PRD §9). AES-256 in GCM mode (authenticated
 * encryption) using only the JDK's {@code javax.crypto} — no extra dependency and native-image clean.
 *
 * <p>The AES key is derived from the configured {@link AccessProperties#getSecretKey() passphrase} via
 * SHA-256, so operators can supply any string; prod should supply a high-entropy value. Each
 * {@link #encrypt} draws a fresh random 96-bit IV (the GCM-recommended size) and prepends it to the
 * ciphertext, so encrypting the same plaintext twice yields different output. The stored form is
 * Base64 of {@code IV || ciphertext+tag}; {@link #decrypt} splits the IV back off.
 */
@Component
public class SecretCipher {

    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int IV_LENGTH = 12;        // 96-bit nonce, recommended for GCM
    private static final int TAG_LENGTH_BITS = 128; // full-length GCM auth tag

    private final SecretKeySpec key;
    private final SecureRandom random = new SecureRandom();

    public SecretCipher(AccessProperties properties) {
        String passphrase = properties.getSecretKey();
        if (passphrase == null || passphrase.isBlank()) {
            throw new IllegalStateException(
                    "envdashboard.access.secret-key must be set so Server/Database secrets can be "
                            + "encrypted at rest (ADR-0005)");
        }
        this.key = deriveKey(passphrase);
    }

    /** Encrypts plaintext to the at-rest form: Base64({@code IV || ciphertext+tag}). */
    public String encrypt(String plaintext) {
        try {
            byte[] iv = new byte[IV_LENGTH];
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH_BITS, iv));
            byte[] ciphertext = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));

            byte[] combined = new byte[iv.length + ciphertext.length];
            System.arraycopy(iv, 0, combined, 0, iv.length);
            System.arraycopy(ciphertext, 0, combined, iv.length, ciphertext.length);
            return Base64.getEncoder().encodeToString(combined);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to encrypt secret", e);
        }
    }

    /** Reverses {@link #encrypt}. Throws if the input was tampered with or encrypted under another key. */
    public String decrypt(String stored) {
        try {
            byte[] combined = Base64.getDecoder().decode(stored);
            if (combined.length <= IV_LENGTH) {
                throw new IllegalArgumentException("Stored secret is too short to contain an IV");
            }
            byte[] iv = new byte[IV_LENGTH];
            System.arraycopy(combined, 0, iv, 0, IV_LENGTH);
            byte[] ciphertext = new byte[combined.length - IV_LENGTH];
            System.arraycopy(combined, IV_LENGTH, ciphertext, 0, ciphertext.length);

            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH_BITS, iv));
            return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to decrypt secret", e);
        }
    }

    private static SecretKeySpec deriveKey(String passphrase) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(passphrase.getBytes(StandardCharsets.UTF_8));
            return new SecretKeySpec(digest, "AES"); // 32 bytes -> AES-256
        } catch (Exception e) {
            throw new IllegalStateException("Failed to derive encryption key", e);
        }
    }
}
