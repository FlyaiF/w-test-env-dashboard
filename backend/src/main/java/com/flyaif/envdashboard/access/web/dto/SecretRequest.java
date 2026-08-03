package com.flyaif.envdashboard.access.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Write payload to set a resource's secret. The plaintext is encrypted before it is stored. The
 * length cap keeps the encrypted form (Base64 of IV + ciphertext + tag) within the 2000-char
 * {@code secret_enc} column, so an oversize secret is rejected as a 400 rather than failing at the
 * database with a 500.
 */
public record SecretRequest(
        @NotBlank @Size(max = 1024) String secret
) {
}
