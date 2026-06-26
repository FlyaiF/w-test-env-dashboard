package com.flyaif.envdashboard.legacyimport;

/**
 * The parsed pieces of a legacy database slot ({@code E_YWDB} / {@code E_ZJDB}), which legacy data
 * stores as a JDBC URL or bare {@code host:port/service} connection string. Maps onto the new
 * {@link com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor}; {@link #host} is the only
 * guaranteed field, the rest are null when the source omitted them.
 *
 * <p>{@link #password} is captured but not persisted — secrets are brokered in slice 06 (ADR-0005).
 */
public record LegacyDbRef(String host, Integer port, String serviceName, String username, String password) {
}
