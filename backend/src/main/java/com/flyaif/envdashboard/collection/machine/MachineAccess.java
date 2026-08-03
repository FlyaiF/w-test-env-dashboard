package com.flyaif.envdashboard.collection.machine;

import com.flyaif.envdashboard.inventory.domain.Database;

import java.time.Instant;

/**
 * The single shared "obtain something from a machine" capability (PRD §4). It is the one place that
 * actually touches the network, so every {@link com.flyaif.envdashboard.collection.probe.VersionProbe}
 * goes through it and stays deterministic under test (a fake stands in for the real reach).
 *
 * <p>Slice 05 backs the two settled probe strategies — HTTP and db-query — using the slice-04
 * connection descriptors. OS-dependent command access over SSH/WinRM (for the future SSH_FILE /
 * COMMAND probes) is the next operation to add here; it is deliberately absent until those probes
 * land, to avoid a speculative seam.
 */
public interface MachineAccess {

    /**
     * HTTP GET the given URL and return the response body. Throws (not returns) on a transport error
     * or non-2xx status, so the calling probe records a FAILED result for that one Component.
     */
    String httpGet(String url);

    /**
     * Open a JDBC connection to the Database (driver chosen by its {@link Database#getType()} and the
     * slice-04 {@code ConnectionDescriptor}), run the query, and return the first column of the first
     * row as text — or {@code null} when the query yields no rows, so a probe can tell "the data is
     * absent" apart from "the machine is unreachable". Throws on any connection/SQL error.
     */
    String queryScalar(Database database, String sql);

    /**
     * Like {@link #queryScalar} but reads the first column of the first row as a timestamp — or
     * {@code null} when the query yields no rows or the value is SQL NULL. The value is interpreted
     * in this JVM's zone (Oracle {@code DATE} carries none). Throws on any connection/SQL error.
     */
    Instant queryInstant(Database database, String sql);
}
