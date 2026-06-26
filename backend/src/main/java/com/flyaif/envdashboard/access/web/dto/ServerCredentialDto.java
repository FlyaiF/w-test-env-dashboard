package com.flyaif.envdashboard.access.web.dto;

/**
 * An on-demand SSH credential bundle for a Server (ADR-0005): the connection descriptor plus the
 * decrypted secret, delivered to the client just-in-time to launch its own SSH tool. The client holds
 * nothing durable — this is fetched per launch and discarded. {@code secret} is null if none is stored.
 */
public record ServerCredentialDto(
        Long serverId,
        String host,
        Integer port,
        String username,
        String secret
) {
}
