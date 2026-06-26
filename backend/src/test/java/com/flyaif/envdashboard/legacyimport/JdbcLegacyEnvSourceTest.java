package com.flyaif.envdashboard.legacyimport;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.Statement;
import java.sql.Timestamp;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Verifies the JDBC read maps every legacy column (and a null timestamp) into a {@link LegacyEnvRow},
 * against a throwaway H2 table shaped like the real {@code TENVINFO} — no Spring context needed.
 */
class JdbcLegacyEnvSourceTest {

    private DataSource freshH2(String dbName) throws Exception {
        DriverManagerDataSource ds = new DriverManagerDataSource(
                "jdbc:h2:mem:" + dbName + ";DB_CLOSE_DELAY=-1", "sa", "");
        try (Connection c = ds.getConnection(); Statement s = c.createStatement()) {
            s.execute("""
                    CREATE TABLE TENVINFO (
                        E_NO NUMBER(19) PRIMARY KEY,
                        E_NAME VARCHAR(200), E_YWDB VARCHAR(500), E_ZJDB VARCHAR(500),
                        E_URL VARCHAR(500), E_VERSION VARCHAR(200), E_UPDATETIME TIMESTAMP,
                        E_SEEURL VARCHAR(500), E_WEBSERVERADDR VARCHAR(500), E_WEBLOGPATH VARCHAR(500),
                        E_MEMO VARCHAR(1000), E_DBTYPE VARCHAR(40)
                    )""");
        }
        return ds;
    }

    @Test
    void readsAllColumnsOrderedByENo() throws Exception {
        DataSource ds = freshH2("legacy_read");
        try (Connection c = ds.getConnection(); Statement s = c.createStatement()) {
            s.execute("""
                    INSERT INTO TENVINFO VALUES
                        (2, 'Beta', 'app/pw@db:1521/B', NULL, 'http://b', '1.0',
                         TIMESTAMP '2026-06-20 08:30:00', NULL, 'h:22&u/p', '/log/b', 'm', 'oracle')""");
            s.execute("""
                    INSERT INTO TENVINFO (E_NO, E_NAME) VALUES (1, 'Alpha')""");
        }

        List<LegacyEnvRow> rows = new JdbcLegacyEnvSource(ds, "TENVINFO").readAll();

        assertThat(rows).hasSize(2);
        assertThat(rows.get(0).eNo()).isEqualTo(1L);   // ordered by E_NO
        assertThat(rows.get(0).name()).isEqualTo("Alpha");
        assertThat(rows.get(0).updateTime()).isNull();

        LegacyEnvRow beta = rows.get(1);
        assertThat(beta.name()).isEqualTo("Beta");
        assertThat(beta.businessDb()).isEqualTo("app/pw@db:1521/B");
        assertThat(beta.webServerAddr()).isEqualTo("h:22&u/p");
        assertThat(beta.webLogPath()).isEqualTo("/log/b");
        assertThat(beta.dbType()).isEqualTo("oracle");
        // Compared via the same local-zone conversion the driver uses, so it holds in any JVM timezone.
        assertThat(beta.updateTime()).isEqualTo(Timestamp.valueOf("2026-06-20 08:30:00").toInstant());
    }

    @Test
    void rejectsUnsafeTableName() throws Exception {
        DataSource ds = freshH2("legacy_guard");
        assertThatThrownBy(() -> new JdbcLegacyEnvSource(ds, "TENVINFO; DROP TABLE X"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
