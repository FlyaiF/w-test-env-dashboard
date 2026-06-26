package com.flyaif.envdashboard.collection.machine;

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
import java.sql.Statement;
import java.time.Duration;

/**
 * Real {@link MachineAccess}: HTTP over {@link HttpClient}, databases over JDBC with the driver chosen
 * by {@link DatabaseType}. Bounded timeouts keep one unreachable host from stalling a Collection sweep.
 *
 * <p>Drivers are loaded at runtime by coordinate (ojdbc8 / Dameng / OceanBase, PRD §9); there is no
 * compile-time dependency on driver classes here — only {@code java.sql}. The connection password is
 * not yet supplied (credential brokering is slice 06, ADR-0005), so connections use the descriptor's
 * username with an empty password for now.
 */
@Component
public class JdbcHttpMachineAccess implements MachineAccess {

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

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
        String url = jdbcUrl(database);
        ConnectionDescriptor conn = database.getConnection();
        String username = conn == null ? null : conn.getUsername();
        try (Connection connection = DriverManager.getConnection(url, username, "");
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            if (!rows.next()) {
                throw new MachineAccessException("Query returned no rows: " + sql);
            }
            return rows.getString(1);
        } catch (MachineAccessException e) {
            throw e;
        } catch (Exception e) {
            throw new MachineAccessException(
                    "Failed querying database " + database.getId() + ": " + e.getMessage(), e);
        }
    }

    /** Build the JDBC URL for the database's engine from its non-secret connection descriptor. */
    private static String jdbcUrl(Database database) {
        ConnectionDescriptor c = database.getConnection();
        if (c == null) {
            throw new MachineAccessException("Database " + database.getId() + " has no connection descriptor");
        }
        DatabaseType type = database.getType();
        String host = c.getHost();
        Integer port = c.getPort();
        String service = c.getServiceName();
        return switch (type == null ? DatabaseType.OTHER : type) {
            case ORACLE -> "jdbc:oracle:thin:@//" + host + ":" + port + "/" + service;
            case DAMENG -> "jdbc:dm://" + host + ":" + port;
            case OCEANBASE -> "jdbc:oceanbase://" + host + ":" + port + "/" + service;
            case OTHER -> throw new MachineAccessException(
                    "No JDBC driver mapping for database type OTHER (database " + database.getId() + ")");
        };
    }
}
