package com.flyaif.envdashboard.legacyimport;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Reads raw {@code TENVINFO} rows from the legacy database over plain JDBC. The legacy store is a
 * different database from the backend's own (new-schema) datasource, so this source owns its own
 * {@link DataSource} rather than reusing the application's. The interesting interpretation of the
 * values lives in {@link TenvinfoImporter}; this class only ferries columns into {@link LegacyEnvRow}.
 */
public class JdbcLegacyEnvSource implements LegacyEnvSource {

    /** Guards the operator-supplied table name, which is interpolated into the query. */
    private static final Pattern SAFE_IDENTIFIER = Pattern.compile("[A-Za-z_][A-Za-z0-9_.]*");

    private final DataSource dataSource;
    private final String table;

    public JdbcLegacyEnvSource(DataSource dataSource, String table) {
        if (!SAFE_IDENTIFIER.matcher(table).matches()) {
            throw new IllegalArgumentException("Unsafe legacy table name: " + table);
        }
        this.dataSource = dataSource;
        this.table = table;
    }

    @Override
    public List<LegacyEnvRow> readAll() {
        String sql = "SELECT E_NO, E_NAME, E_YWDB, E_ZJDB, E_URL, E_VERSION, E_UPDATETIME, "
                + "E_SEEURL, E_WEBSERVERADDR, E_WEBLOGPATH, E_MEMO, E_DBTYPE FROM " + table + " ORDER BY E_NO";

        List<LegacyEnvRow> rows = new ArrayList<>();
        try (Connection connection = dataSource.getConnection();
             Statement statement = connection.createStatement();
             ResultSet rs = statement.executeQuery(sql)) {
            while (rs.next()) {
                rows.add(mapRow(rs));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Failed to read legacy table " + table, e);
        }
        return rows;
    }

    private LegacyEnvRow mapRow(ResultSet rs) throws SQLException {
        // E_UPDATETIME is an Oracle DATE with no timezone (AGENTS.md gotcha): the legacy stack wrote it
        // with SYSDATE and read it back as local wall-clock. We mirror that here — getTimestamp()
        // interprets the value in the JVM's default zone and toInstant() pins it to a point in time.
        // Run the import with TZ set to the legacy data's zone so version-update times migrate faithfully.
        Timestamp updateTime = rs.getTimestamp("E_UPDATETIME");
        Instant updateInstant = updateTime == null ? null : updateTime.toInstant();
        return new LegacyEnvRow(
                rs.getLong("E_NO"),
                rs.getString("E_NAME"),
                rs.getString("E_YWDB"),
                rs.getString("E_ZJDB"),
                rs.getString("E_URL"),
                rs.getString("E_VERSION"),
                updateInstant,
                rs.getString("E_SEEURL"),
                rs.getString("E_WEBSERVERADDR"),
                rs.getString("E_WEBLOGPATH"),
                rs.getString("E_MEMO"),
                rs.getString("E_DBTYPE"));
    }
}
