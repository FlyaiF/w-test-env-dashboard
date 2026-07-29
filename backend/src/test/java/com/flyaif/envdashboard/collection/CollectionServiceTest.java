package com.flyaif.envdashboard.collection;

import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
import com.flyaif.envdashboard.collection.machine.MachineAccessException;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import java.time.Instant;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;

/**
 * Drives the real HTTP and db-query probes through the {@link CollectionService} with a faked
 * {@link MachineAccess}. Proves the two strategies coexist behind one extension point, that Collection
 * writes version/status/last-collected onto each Component, and — the headline guarantee — that one
 * failing or unsupported probe degrades only its own Component and never blanks its siblings.
 */
@SpringBootTest
class CollectionServiceTest {

    @Autowired
    private CollectionService collection;

    @Autowired
    private EnvironmentRepository environments;

    @Autowired
    private ServerRepository servers;

    @Autowired
    private DatabaseRepository databases;

    @MockBean
    private MachineAccess machineAccess;

    @BeforeEach
    void clean() {
        environments.deleteAll();
        servers.deleteAll();
        databases.deleteAll();
    }

    private static ComponentDto byRole(EnvironmentDto env, ComponentRole role) {
        return env.components().stream()
                .filter(c -> role.name().equals(c.role()))
                .findFirst()
                .orElseThrow();
    }

    @Test
    void collectsEachComponentIndependentlyAndNeverBlanksSiblingsOnFailure() {
        given(machineAccess.httpGet("http://gw/version")).willReturn("  9.9.9\n");
        given(machineAccess.httpGet("http://bad/version"))
                .willThrow(new MachineAccessException("connection refused"));
        given(machineAccess.queryScalar(any(Database.class), anyString())).willReturn("7.7.7");
        given(machineAccess.queryInstant(any(Database.class), anyString()))
                .willReturn(Instant.parse("2026-06-30T18:00:00Z"));

        Database appDb = databases.save(new Database("business", DatabaseType.ORACLE, null));

        Environment env = new Environment("测试环境 Collect", null);

        Component httpOk = new Component(ComponentRole.GATEWAY);   // HTTP probe, reachable
        httpOk.setVersionProbe(VersionProbeKind.HTTP);
        httpOk.setUrl("http://gw/version");
        env.addComponent(httpOk);

        Component dbOk = new Component(ComponentRole.APP);         // db-query probe, reachable
        dbOk.setVersionProbe(VersionProbeKind.DB);
        dbOk.setDatabaseIds(Set.of(appDb.getId()));
        env.addComponent(dbOk);

        Component httpFail = new Component(ComponentRole.UI);      // HTTP probe, unreachable
        httpFail.setVersionProbe(VersionProbeKind.HTTP);
        httpFail.setUrl("http://bad/version");
        httpFail.setVersion("1.0.0");                             // known-good prior version
        env.addComponent(httpFail);

        Component noProbe = new Component(ComponentRole.PRIVATE_PROTO); // no probe strategy
        noProbe.setVersionProbe(VersionProbeKind.NONE);
        env.addComponent(noProbe);

        Long envId = environments.save(env).getId();

        EnvironmentDto refreshed = collection.refresh(envId);

        ComponentDto okComp = byRole(refreshed, ComponentRole.GATEWAY);
        assertThat(okComp.collectionStatus()).isEqualTo("OK");
        assertThat(okComp.version()).isEqualTo("9.9.9");          // trimmed
        assertThat(okComp.lastCollectedAt()).isNotNull();
        assertThat(okComp.collectionDetail()).isNull();           // OK clears any prior detail

        ComponentDto dbComp = byRole(refreshed, ComponentRole.APP);
        assertThat(dbComp.collectionStatus()).isEqualTo("OK");
        assertThat(dbComp.version()).isEqualTo("7.7.7");
        assertThat(dbComp.versionUpdatedAt()).isEqualTo(Instant.parse("2026-06-30T18:00:00Z"));

        ComponentDto failComp = byRole(refreshed, ComponentRole.UI);
        assertThat(failComp.collectionStatus()).isEqualTo("FAILED");
        assertThat(failComp.version()).isEqualTo("1.0.0");        // NOT blanked by the failure
        assertThat(failComp.lastCollectedAt()).isNotNull();       // but the attempt is recorded
        assertThat(failComp.collectionDetail()).contains("connection refused");

        ComponentDto unsupportedComp = byRole(refreshed, ComponentRole.PRIVATE_PROTO);
        assertThat(unsupportedComp.collectionStatus()).isEqualTo("UNSUPPORTED");
        assertThat(unsupportedComp.collectionDetail()).isNotNull();
    }

    @Test
    void refreshAllSweepsEveryComponentAcrossEnvironments() {
        given(machineAccess.httpGet(anyString())).willReturn("5.0.0");

        Environment a = new Environment("ENV-A", null);
        Component ca = new Component(ComponentRole.APP);
        ca.setVersionProbe(VersionProbeKind.HTTP);
        ca.setUrl("http://a/version");
        a.addComponent(ca);

        Environment b = new Environment("ENV-B", null);
        Component cb = new Component(ComponentRole.APP);
        cb.setVersionProbe(VersionProbeKind.HTTP);
        cb.setUrl("http://b/version");
        b.addComponent(cb);

        environments.saveAll(List.of(a, b));

        int collected = collection.refreshAll();

        assertThat(collected).isEqualTo(2);
        assertThat(environments.findAll())
                .flatMap(Environment::getComponents)
                .allMatch(c -> "5.0.0".equals(c.getVersion()))
                .allMatch(c -> c.getLastCollectedAt() != null);
    }
}
