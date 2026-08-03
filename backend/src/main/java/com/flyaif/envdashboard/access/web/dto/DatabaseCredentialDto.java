package com.flyaif.envdashboard.access.web.dto;

/**
 * An on-demand DB credential bundle for a Database (ADR-0005): the connection descriptor, a
 * ready-to-use {@code jdbcUrl} (null for engines with no known driver), and the decrypted secret —
 * delivered just-in-time to launch the client's own DB tool. Nothing is cached on the client.
 * {@code secret} is null if none is stored.
 */
public record DatabaseCredentialDto(
        Long databaseId,
        String type,
        String host,
        Integer port,
        String serviceName,
        String username,
        String jdbcUrl,
        String secret
) {
}
