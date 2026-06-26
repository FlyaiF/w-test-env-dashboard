package com.flyaif.envdashboard.legacyimport;

import java.util.List;

/**
 * Supplies the legacy {@code TENVINFO} rows to import. Abstracting the read decouples the mapping
 * logic (the interesting, well-tested part) from where the rows come from: production reads from the
 * legacy Oracle via {@link JdbcLegacyEnvSource}; tests hand in an in-memory list.
 */
public interface LegacyEnvSource {

    List<LegacyEnvRow> readAll();
}
