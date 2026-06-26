package com.flyaif.envdashboard.legacyimport;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class LegacyValueRedactorTest {

    @Test
    void masksSshCompositeCredentials() {
        assertThat(LegacyValueRedactor.redact("10.0.1.10:22&deploy/secret"))
                .isEqualTo("10.0.1.10:22&***");
    }

    @Test
    void masksPlainDsnUserinfo() {
        assertThat(LegacyValueRedactor.redact("scott/tiger@dbhost:1521/XE"))
                .isEqualTo("***@dbhost:1521/XE");
    }

    @Test
    void masksOracleThinUserinfoKeepingPrefix() {
        assertThat(LegacyValueRedactor.redact("jdbc:oracle:thin:app/pw@10.0.2.5:1521/ORCL"))
                .isEqualTo("jdbc:oracle:thin:***@10.0.2.5:1521/ORCL");
    }

    @Test
    void masksUrlUserinfo() {
        assertThat(LegacyValueRedactor.redact("oracle://app:pw@10.0.2.7:1521/SVC"))
                .isEqualTo("oracle://***@10.0.2.7:1521/SVC");
    }

    @Test
    void masksPasswordQueryParameterButKeepsHostAndUser() {
        assertThat(LegacyValueRedactor.redact(
                "jdbc:oceanbase:oracle://10.20.161.98:2881/obfz?connectTimeout=5000&user=u@tenant&password=handsome"))
                .isEqualTo("jdbc:oceanbase:oracle://10.20.161.98:2881/obfz?connectTimeout=5000&user=u@tenant&password=***");
    }

    @Test
    void leavesCredentialFreeValuesUntouched() {
        assertThat(LegacyValueRedactor.redact("dbhost:1521/ORCL")).isEqualTo("dbhost:1521/ORCL");
        assertThat(LegacyValueRedactor.redact(":::garbage")).isEqualTo(":::garbage");
        assertThat(LegacyValueRedactor.redact(null)).isNull();
    }
}
