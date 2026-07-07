package com.flyaif.envdashboard.collection.machine;

import com.flyaif.envdashboard.access.SecretStore;
import com.flyaif.envdashboard.inventory.JdbcUrlBuilder;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;

/**
 * Real {@link MachineAccess}: HTTP over {@link HttpClient}, databases over JDBC with the driver chosen
 * by {@link DatabaseType}. Bounded timeouts keep one unreachable host from stalling a Collection sweep.
 *
 * <p>Drivers are loaded at runtime by coordinate (ojdbc8 / Dameng / OceanBase, PRD §9); there is no
 * compile-time dependency on driver classes here — only {@code java.sql}. The connection password is
 * brokered from the encrypted {@link SecretStore} (ADR-0005, slice 06); a Database with no stored
 * secret connects with an empty password (e.g. trust auth) rather than failing the probe outright.
 */
@Component
public class JdbcHttpMachineAccess implements MachineAccess {

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    private final SecretStore secrets;

    public JdbcHttpMachineAccess(SecretStore secrets) {
        this.secrets = secrets;
    }

    @Override
    public String httpGet(String url) {
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(10))
                    .GET()
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() / 100 != 2) {
                throw new MachineAccessException("HTTP " + response.statusCode() + " from " + url);
            }
            return response.body();
        } catch (MachineAccessException e) {
            throw e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new MachineAccessException("Interrupted fetching " + url, e);
        } catch (Exception e) {
            throw new MachineAccessException("Failed to GET " + url + ": " + e.getMessage(), e);
        }
    }

    @Override
    public String queryScalar(Database database, String sql) {
        return querySingle(database, sql, rows -> rows.getString(1));
    }

    @Override
    public Instant queryInstant(Database database, String sql) {
        return querySingle(database, sql, rows -> {
            Timestamp value = rows.getTimestamp(1);
            return value == null ? null : value.toInstant();
        });
    }

    /** Reads column 1 of the first row via {@code reader}, or returns null when there is no row. */
    private <T> T querySingle(Database database, String sql, ScalarReader<T> reader) {
        String url = JdbcUrlBuilder.forDatabase(database);
        if (url == null) {
            throw new MachineAccessException(
                    "No JDBC URL for database " + database.getId()
                            + " (missing connection descriptor or unsupported type)");
        }
        ConnectionDescriptor conn = database.getConnection();
        String username = conn == null ? null : conn.getUsername();
        String password = secrets.databaseSecret(database.getId()).orElse("");
        try (Connection connection = DriverManager.getConnection(url, username, password);
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            if (!rows.next()) {
                return null;
            }
            return reader.read(rows);
        } catch (Exception e) {
            throw new MachineAccessException(
                    "Failed querying database " + database.getId() + ": " + e.getMessage(), e);
        }
    }

    @FunctionalInterface
    private interface ScalarReader<T> {
        T read(ResultSet rows) throws SQLException;
    }
}
