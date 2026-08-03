package com.flyaif.envdashboard.access;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Unit tests for the at-rest encryption primitive (ADR-0005). */
class SecretCipherTest {

    private static SecretCipher cipherWithKey(String key) {
        AccessProperties properties = new AccessProperties();
        properties.setSecretKey(key);
        return new SecretCipher(properties);
    }

    @Test
    void roundTripsPlaintext() {
        SecretCipher cipher = cipherWithKey("master-key");

        String stored = cipher.encrypt("hunter2");

        assertThat(stored).isNotEqualTo("hunter2"); // not plaintext at rest
        assertThat(cipher.decrypt(stored)).isEqualTo("hunter2");
    }

    @Test
    void encryptingTwiceYieldsDifferentCiphertext() {
        SecretCipher cipher = cipherWithKey("master-key");

        String a = cipher.encrypt("same-secret");
        String b = cipher.encrypt("same-secret");

        assertThat(a).isNotEqualTo(b);                 // fresh random IV each time
        assertThat(cipher.decrypt(a)).isEqualTo("same-secret");
        assertThat(cipher.decrypt(b)).isEqualTo("same-secret");
    }

    @Test
    void decryptingTamperedCiphertextFails() {
        SecretCipher cipher = cipherWithKey("master-key");
        String stored = cipher.encrypt("secret");

        // Flip the final character; GCM authentication must reject the altered ciphertext.
        char last = stored.charAt(stored.length() - 1);
        String tampered = stored.substring(0, stored.length() - 1) + (last == 'A' ? 'B' : 'A');

        assertThatThrownBy(() -> cipher.decrypt(tampered))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void cipherUnderOneKeyCannotDecryptAnother() {
        String stored = cipherWithKey("key-one").encrypt("secret");

        assertThatThrownBy(() -> cipherWithKey("key-two").decrypt(stored))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void refusesToStartWithoutAKey() {
        AccessProperties blank = new AccessProperties();
        blank.setSecretKey("   ");

        assertThatThrownBy(() -> new SecretCipher(blank))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("secret-key");
    }
}
