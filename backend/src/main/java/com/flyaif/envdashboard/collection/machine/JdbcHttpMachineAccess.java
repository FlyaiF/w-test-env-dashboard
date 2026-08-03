package com.flyaif.envdashboard.collection.machine;

import com.flyaif.envdashboard.access.SecretStore;
import com.flyaif.envdashboard.inventory.JdbcUrlBuilder;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.SQLFeatureNotSupportedException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.Properties;
import java.util.concurrent.Executor;
import java.util.concurrent.ForkJoinPool;

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

    private static final Object DRIVER_MANAGER_LOGIN_TIMEOUT_LOCK = new Object();
    private static final Executor NETWORK_TIMEOUT_EXECUTOR = ForkJoinPool.commonPool();

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    private final SecretStore secrets;
    private final int loginTimeoutSeconds;
    private final int queryTimeoutSeconds;
    private final int loginTimeoutMillis;
    private final int readTimeoutMillis;
    private final JdbcConnector connector;

    @Autowired
    public JdbcHttpMachineAccess(SecretStore secrets, JdbcAccessProperties properties) {
        this(secrets, properties, JdbcHttpMachineAccess::driverManagerConnect);
    }

    JdbcHttpMachineAccess(SecretStore secrets,
                          JdbcAccessProperties properties,
                          JdbcConnector connector) {
        this.secrets = secrets;
        this.loginTimeoutSeconds = timeoutSeconds(properties.getLoginTimeout(), "login-timeout");
        this.queryTimeoutSeconds = timeoutSeconds(properties.getQueryTimeout(), "query-timeout");
        this.loginTimeoutMillis = timeoutMillis(properties.getLoginTimeout(), "login-timeout");
        this.readTimeoutMillis = timeoutMillis(properties.getReadTimeout(), "read-timeout");
        this.connector = connector;
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
        Properties connectionProperties = connectionProperties(username, password);
        try (Connection connection = connector.connect(url, connectionProperties, loginTimeoutSeconds)) {
            applyReadTimeout(connection);
            try (Statement statement = connection.createStatement()) {
                statement.setQueryTimeout(queryTimeoutSeconds);
                try (ResultSet rows = statement.executeQuery(sql)) {
                    if (!rows.next()) {
                        return null;
                    }
                    return reader.read(rows);
                }
            }
        } catch (Exception e) {
            throw new MachineAccessException(
                    "Failed querying database " + database.getId() + ": " + e.getMessage(), e);
        }
    }

    /**
     * Supply both the standard login bound and driver-specific socket bounds. Unknown connection
     * properties are ignored by JDBC drivers; Oracle and OceanBase each consume their own names.
     */
    private Properties connectionProperties(String username, String password) {
        Properties properties = new Properties();
        if (username != null) {
            properties.setProperty("user", username);
        }
        properties.setProperty("password", password);
        properties.setProperty("connectTimeout", String.valueOf(loginTimeoutMillis));
        properties.setProperty("socketTimeout", String.valueOf(readTimeoutMillis));
        properties.setProperty("oracle.net.CONNECT_TIMEOUT", String.valueOf(loginTimeoutMillis));
        properties.setProperty("oracle.jdbc.ReadTimeout", String.valueOf(readTimeoutMillis));
        return properties;
    }

    private void applyReadTimeout(Connection connection) throws SQLException {
        try {
            connection.setNetworkTimeout(NETWORK_TIMEOUT_EXECUTOR, readTimeoutMillis);
        } catch (SQLFeatureNotSupportedException | AbstractMethodError unsupported) {
            // Older drivers may not implement JDBC 4.1 network timeouts. Their vendor-specific
            // socket property above still supplies the read bound.
        }
    }

    /**
     * DriverManager exposes login timeout as process-global state. Serialize the short configuration
     * window and restore the prior value so version probes do not permanently mutate the application's
     * datasource behavior. Per-driver connectTimeout properties provide a second, connection-local
     * bound for the Oracle/OceanBase drivers used here.
     */
    private static Connection driverManagerConnect(String url,
                                                    Properties properties,
                                                    int loginTimeoutSeconds) throws SQLException {
        synchronized (DRIVER_MANAGER_LOGIN_TIMEOUT_LOCK) {
            int previous = DriverManager.getLoginTimeout();
            try {
                DriverManager.setLoginTimeout(loginTimeoutSeconds);
                return DriverManager.getConnection(url, properties);
            } finally {
                DriverManager.setLoginTimeout(previous);
            }
        }
    }

    private static int timeoutSeconds(Duration duration, String property) {
        requirePositive(duration, property);
        long seconds = duration.getSeconds();
        if (seconds >= Integer.MAX_VALUE) {
            return Integer.MAX_VALUE;
        }
        if (duration.getNano() > 0) {
            seconds++;
        }
        return (int) seconds;
    }

    private static int timeoutMillis(Duration duration, String property) {
        requirePositive(duration, property);
        try {
            return (int) Math.max(1, Math.min(duration.toMillis(), Integer.MAX_VALUE));
        } catch (ArithmeticException overflow) {
            return Integer.MAX_VALUE;
        }
    }

    private static void requirePositive(Duration duration, String property) {
        if (duration == null || duration.isZero() || duration.isNegative()) {
            throw new IllegalArgumentException(
                    "envdashboard.collection.jdbc." + property + " must be greater than zero");
        }
    }

    @FunctionalInterface
    interface JdbcConnector {
        Connection connect(String url, Properties properties, int loginTimeoutSeconds) throws SQLException;
    }

    @FunctionalInterface
    private interface ScalarReader<T> {
        T read(ResultSet rows) throws SQLException;
    }
}
