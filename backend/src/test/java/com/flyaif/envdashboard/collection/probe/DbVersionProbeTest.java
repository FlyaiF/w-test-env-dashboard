package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.CollectionStatus;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

/**
 * The real db-query probe (issue 08): reads the version from {@code tsys_parameter} and the
 * 版本更新时间 from {@code jres_subsystem_rc} of the Component's business Database (role
 * {@link Database#BUSINESS_ROLE}, falling back to the first linked one), with the settled strictness —
 * missing SystemVersion fails, an empty (never-upgraded) jres_subsystem_rc still succeeds without a
 * timestamp.
 */
class DbVersionProbeTest {

    private MachineAccess machineAccess;
    private DbVersionProbe probe;

    @BeforeEach
    void setUp() {
        machineAccess = Mockito.mock(MachineAccess.class);
        probe = new DbVersionProbe(machineAccess);
    }

    private static ProbeContext context(Database... databases) {
        return new ProbeContext(new Component(ComponentRole.APP), null, List.of(databases));
    }

    @Test
    void readsVersionAndVersionUpdatedAtFromTheBusinessDatabase() {
        Database intermediate = new Database("intermediate", DatabaseType.ORACLE, null);
        Database business = new Database(Database.BUSINESS_ROLE, DatabaseType.ORACLE, null);
        Instant updatedAt = Instant.parse("2026-07-01T02:30:00Z");
        given(machineAccess.queryScalar(business, DbVersionProbe.VERSION_QUERY)).willReturn(" TA6.0 ");
        given(machineAccess.queryInstant(business, DbVersionProbe.VERSION_UPDATED_AT_QUERY))
                .willReturn(updatedAt);

        // Linked order puts the intermediate DB first — the business role must still win.
        ProbeResult result = probe.probe(context(intermediate, business));

        assertThat(result.status()).isEqualTo(CollectionStatus.OK);
        assertThat(result.version()).isEqualTo("TA6.0");
        assertThat(result.versionUpdatedAt()).isEqualTo(updatedAt);
        verify(machineAccess, never()).queryScalar(eq(intermediate), anyString());
    }

    @Test
    void roleMatchIsCaseInsensitive() {
        Database business = new Database("Business", DatabaseType.ORACLE, null);
        given(machineAccess.queryScalar(business, DbVersionProbe.VERSION_QUERY)).willReturn("1.2.3");

        assertThat(probe.probe(context(business)).status()).isEqualTo(CollectionStatus.OK);
    }

    @Test
    void fallsBackToTheFirstLinkedDatabaseWhenNoBusinessRole() {
        Database first = new Database("something-else", DatabaseType.ORACLE, null);
        Database second = new Database("another", DatabaseType.ORACLE, null);
        given(machineAccess.queryScalar(first, DbVersionProbe.VERSION_QUERY)).willReturn("2.0");

        ProbeResult result = probe.probe(context(first, second));

        assertThat(result.status()).isEqualTo(CollectionStatus.OK);
        assertThat(result.version()).isEqualTo("2.0");
    }

    @Test
    void failsWhenNoDatabaseIsLinked() {
        ProbeResult result = probe.probe(context());

        assertThat(result.status()).isEqualTo(CollectionStatus.FAILED);
        assertThat(result.detail()).contains(Database.BUSINESS_ROLE);
    }

    @Test
    void failsWhenTheBusinessDatabaseHasNoSystemVersionParameter() {
        Database business = new Database(Database.BUSINESS_ROLE, DatabaseType.ORACLE, null);
        given(machineAccess.queryScalar(business, DbVersionProbe.VERSION_QUERY)).willReturn(null);

        ProbeResult result = probe.probe(context(business));

        assertThat(result.status()).isEqualTo(CollectionStatus.FAILED);
        assertThat(result.detail()).contains("SystemVersion");
        // The failure short-circuits: no point asking for a timestamp without a version.
        verify(machineAccess, never()).queryInstant(any(Database.class), anyString());
    }

    @Test
    void succeedsWithoutTimestampWhenNoSchemaChangeHasEverRun() {
        Database business = new Database(Database.BUSINESS_ROLE, DatabaseType.ORACLE, null);
        given(machineAccess.queryScalar(business, DbVersionProbe.VERSION_QUERY)).willReturn("3.1");
        given(machineAccess.queryInstant(business, DbVersionProbe.VERSION_UPDATED_AT_QUERY))
                .willReturn(null);

        ProbeResult result = probe.probe(context(business));

        assertThat(result.status()).isEqualTo(CollectionStatus.OK);
        assertThat(result.version()).isEqualTo("3.1");
        assertThat(result.versionUpdatedAt()).isNull();
    }
}
