package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class JdbcUrlBuilderTest {

    private static final ConnectionDescriptor CONNECTION =
            new ConnectionDescriptor("db.example", 2881, "APP", "dashboard");

    @Test
    void buildsOracleServiceUrl() {
        Database database = new Database("business", DatabaseType.ORACLE, CONNECTION);

        assertThat(JdbcUrlBuilder.forDatabase(database))
                .isEqualTo("jdbc:oracle:thin:@//db.example:2881/APP");
    }

    @Test
    void buildsDamengUrl() {
        Database database = new Database("business", DatabaseType.DAMENG, CONNECTION);

        assertThat(JdbcUrlBuilder.forDatabase(database)).isEqualTo("jdbc:dm://db.example:2881");
    }

    @Test
    void buildsOceanBaseOracleModeUrl() {
        Database database = new Database("business", DatabaseType.OCEANBASE, CONNECTION);

        assertThat(JdbcUrlBuilder.forDatabase(database))
                .isEqualTo("jdbc:oceanbase://db.example:2881/APP");
    }

    @Test
    void usesDeterministicEnginePortsWhenDescriptorOmitsOne() {
        ConnectionDescriptor portless = new ConnectionDescriptor("db.example", null, "APP", "dashboard");

        assertThat(JdbcUrlBuilder.forDatabase(new Database("business", DatabaseType.ORACLE, portless)))
                .isEqualTo("jdbc:oracle:thin:@//db.example:1521/APP");
        assertThat(JdbcUrlBuilder.forDatabase(new Database("business", DatabaseType.DAMENG, portless)))
                .isEqualTo("jdbc:dm://db.example:5236");
        assertThat(JdbcUrlBuilder.forDatabase(new Database("business", DatabaseType.OCEANBASE, portless)))
                .isEqualTo("jdbc:oceanbase://db.example:2881/APP");
    }

    @Test
    void unsupportedOrMissingDescriptorHasNoUrl() {
        assertThat(JdbcUrlBuilder.forDatabase(new Database("business", DatabaseType.OTHER, CONNECTION)))
                .isNull();
        assertThat(JdbcUrlBuilder.forDatabase(new Database("business", DatabaseType.ORACLE, null)))
                .isNull();
    }
}
