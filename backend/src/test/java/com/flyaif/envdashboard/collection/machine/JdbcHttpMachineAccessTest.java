package com.flyaif.envdashboard.collection.machine;

import com.flyaif.envdashboard.access.SecretStore;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.util.Optional;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class JdbcHttpMachineAccessTest {

    @Test
    void appliesConfigurableLoginQueryAndReadBounds() throws Exception {
        SecretStore secrets = mock(SecretStore.class);
        when(secrets.databaseSecret(null)).thenReturn(Optional.of("db-secret"));

        Connection connection = mock(Connection.class);
        Statement statement = mock(Statement.class);
        ResultSet rows = mock(ResultSet.class);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.executeQuery("select version from dual")).thenReturn(rows);
        when(rows.next()).thenReturn(true);
        when(rows.getString(1)).thenReturn("4.2.0");

        AtomicReference<String> connectedUrl = new AtomicReference<>();
        AtomicReference<Properties> connectedProperties = new AtomicReference<>();
        AtomicInteger loginSeconds = new AtomicInteger();

        JdbcAccessProperties properties = new JdbcAccessProperties();
        properties.setLoginTimeout(Duration.ofMillis(1_200));
        properties.setQueryTimeout(Duration.ofMillis(2_300));
        properties.setReadTimeout(Duration.ofMillis(3_400));

        JdbcHttpMachineAccess access = new JdbcHttpMachineAccess(secrets, properties,
                (url, props, timeout) -> {
                    connectedUrl.set(url);
                    connectedProperties.set(props);
                    loginSeconds.set(timeout);
                    return connection;
                });
        Database database = new Database("business", DatabaseType.OCEANBASE,
                new ConnectionDescriptor("ob.example", 2881, "APP", "tenant-user"));

        assertThat(access.queryScalar(database, "select version from dual")).isEqualTo("4.2.0");
        assertThat(connectedUrl.get()).isEqualTo("jdbc:oceanbase://ob.example:2881/APP");
        assertThat(loginSeconds.get()).isEqualTo(2); // JDBC API accepts whole seconds, rounded up.
        assertThat(connectedProperties.get())
                .containsEntry("user", "tenant-user")
                .containsEntry("password", "db-secret")
                .containsEntry("connectTimeout", "1200")
                .containsEntry("socketTimeout", "3400")
                .containsEntry("oracle.net.CONNECT_TIMEOUT", "1200")
                .containsEntry("oracle.jdbc.ReadTimeout", "3400");
        verify(connection).setNetworkTimeout(any(Executor.class), eq(3_400));
        verify(statement).setQueryTimeout(3);
    }

    @Test
    void abortsAConnectionWhoseCloseHangsPastTheOperationTimeout() throws Exception {
        SecretStore secrets = mock(SecretStore.class);
        when(secrets.databaseSecret(null)).thenReturn(Optional.empty());

        // Reproduces Oracle's logoff blocking forever on a half-dead socket: close() only returns
        // once abort() tears the connection down.
        CountDownLatch abortedLatch = new CountDownLatch(1);
        Connection connection = mock(Connection.class);
        Statement statement = mock(Statement.class);
        ResultSet rows = mock(ResultSet.class);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.executeQuery("select version from dual")).thenReturn(rows);
        when(rows.next()).thenReturn(true);
        when(rows.getString(1)).thenReturn("4.2.0");
        doAnswer(invocation -> {
            abortedLatch.await(30, TimeUnit.SECONDS);
            throw new java.sql.SQLRecoverableException("Closed Connection");
        }).when(connection).close();
        doAnswer(invocation -> {
            abortedLatch.countDown();
            return null;
        }).when(connection).abort(any(Executor.class));

        JdbcAccessProperties properties = new JdbcAccessProperties();
        properties.setOperationTimeout(Duration.ofMillis(200));
        JdbcHttpMachineAccess access = new JdbcHttpMachineAccess(secrets, properties,
                (url, props, timeout) -> connection);
        Database database = new Database("business", DatabaseType.ORACLE,
                new ConnectionDescriptor("ora.example", 1521, "ORCL", "app"));

        assertTimeoutPreemptively(Duration.ofSeconds(10), () ->
                assertThatThrownBy(() -> access.queryScalar(database, "select version from dual"))
                        .isInstanceOf(MachineAccessException.class)
                        .hasMessageContaining("Timed out")
                        .hasMessageContaining("connection aborted"));
        verify(connection).abort(any(Executor.class));
    }

    @Test
    void rejectsNonPositiveTimeoutsInsteadOfSilentlyRunningUnbounded() {
        JdbcAccessProperties properties = new JdbcAccessProperties();
        properties.setReadTimeout(Duration.ZERO);

        assertThatThrownBy(() -> new JdbcHttpMachineAccess(mock(SecretStore.class), properties,
                (url, props, timeout) -> mock(Connection.class)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("read-timeout");
    }
}
