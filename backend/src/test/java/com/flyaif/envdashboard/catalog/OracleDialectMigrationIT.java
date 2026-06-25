package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.OracleContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * De-risks the real Oracle 11g target: proves the V1 migration (sequences, VARCHAR2/NUMBER/TIMESTAMP,
 * ON DELETE CASCADE) and the JPA SEQUENCE generation run on a genuine Oracle, not just H2's Oracle mode.
 *
 * <p>Tagged {@code oracle-it} and excluded from the default Surefire run (it pulls a multi-hundred-MB
 * image). Enable with {@code mvn test -Dgroups=oracle-it -DexcludedGroups=}.
 */
@Tag("oracle-it")
@Testcontainers
@SpringBootTest
class OracleDialectMigrationIT {

    @Container
    static final OracleContainer ORACLE =
            new OracleContainer(DockerImageName.parse("gvenzl/oracle-xe:11-slim"));

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", ORACLE::getJdbcUrl);
        registry.add("spring.datasource.username", ORACLE::getUsername);
        registry.add("spring.datasource.password", ORACLE::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "oracle.jdbc.OracleDriver");
    }

    @Autowired
    private EnvironmentRepository repository;

    @Test
    void migrationAndSequencesRunOnRealOracle() {
        Environment env = new Environment("ORA-ENV", "oracle dialect check");
        env.addComponent(new Component(ComponentRole.GATEWAY));
        Long id = repository.save(env).getId();

        assertThat(id).isNotNull();
        Environment reloaded = repository.findById(id).orElseThrow();
        assertThat(reloaded.getComponents()).hasSize(1);
    }
}
