package com.flyaif.envdashboard.inventory;

import java.util.Set;

/**
 * Read-only view of "does this resource have a stored secret?" for the Inventory read DTOs
 * (`hasSecret`). Only presence crosses this seam — never secret material, so the ADR-0005 boundary
 * (plaintext exists only inside Access Brokering) is preserved. Defined here and implemented by the
 * access module so the dependency direction stays access → inventory.
 */
public interface SecretPresence {

    boolean serverHasSecret(Long serverId);

    boolean databaseHasSecret(Long databaseId);

    /** Bulk form for list endpoints: one query instead of one exists-check per row. */
    Set<Long> serverIdsWithSecret();

    Set<Long> databaseIdsWithSecret();
}
