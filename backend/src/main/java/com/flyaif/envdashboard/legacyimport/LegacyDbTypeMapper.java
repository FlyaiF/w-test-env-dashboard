package com.flyaif.envdashboard.legacyimport;

import com.flyaif.envdashboard.inventory.domain.DatabaseType;

/**
 * Maps the legacy {@code E_DBTYPE} column — a grab-bag of numeric codes and free-text engine names —
 * onto the new {@link DatabaseType} enum. Mirrors the Go sidecar's {@code NormalizeRuntimeDBType} so
 * the import agrees with how the legacy system already interpreted those codes. Anything unrecognised
 * maps to {@link DatabaseType#OTHER} (never dropped — the row stays legible for human follow-up).
 */
public final class LegacyDbTypeMapper {

    private LegacyDbTypeMapper() {
    }

    public static DatabaseType map(String raw) {
        String value = raw == null ? "" : raw.trim().toLowerCase().replace('_', '-').replace(' ', '-');
        return switch (value) {
            case "", "0", "ora", "oracle" -> DatabaseType.ORACLE;
            case "2", "dm", "dameng", "dm8" -> DatabaseType.DAMENG;
            case "1", "ob", "ob-oracle", "oceanbase", "oceanbase-oracle", "oceanbaseoracle" -> DatabaseType.OCEANBASE;
            default -> DatabaseType.OTHER;
        };
    }
}
