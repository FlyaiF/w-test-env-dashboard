package com.flyaif.envdashboard.catalog.web.dto;

import java.util.Set;

/**
 * Set a Component's references into the Resource Inventory: the Server it runs-on (or null to
 * unlink) and the Databases it uses (0..N; null/empty clears them). Replaces the existing links.
 */
public record ComponentLinksRequest(
        Long serverId,
        Set<Long> databaseIds
) {
}
