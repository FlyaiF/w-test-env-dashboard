package com.flyaif.envdashboard.legacyimport;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class LegacyDbSlotParserTest {

    @Test
    void parsesOracleThinWithCredentials() {
        LegacyDbRef ref = LegacyDbSlotParser.parse("jdbc:oracle:thin:app/pw@10.0.2.5:1521/ORCL").orElseThrow();

        assertThat(ref.host()).isEqualTo("10.0.2.5");
        assertThat(ref.port()).isEqualTo(1521);
        assertThat(ref.serviceName()).isEqualTo("ORCL");
        assertThat(ref.username()).isEqualTo("app");
        assertThat(ref.password()).isEqualTo("pw");
    }

    @Test
    void parsesOracleThinNoCredentialsWithSid() {
        LegacyDbRef ref = LegacyDbSlotParser.parse("jdbc:oracle:thin:@10.0.2.5:1521:ORA11").orElseThrow();

        assertThat(ref.host()).isEqualTo("10.0.2.5");
        assertThat(ref.port()).isEqualTo(1521);
        assertThat(ref.serviceName()).isEqualTo("ORA11");
        assertThat(ref.username()).isNull();
        assertThat(ref.password()).isNull();
    }

    @Test
    void parsesPlainCredentials() {
        LegacyDbRef ref = LegacyDbSlotParser.parse("scott/tiger@dbhost:1521/XE").orElseThrow();

        assertThat(ref.host()).isEqualTo("dbhost");
        assertThat(ref.port()).isEqualTo(1521);
        assertThat(ref.serviceName()).isEqualTo("XE");
        assertThat(ref.username()).isEqualTo("scott");
        assertThat(ref.password()).isEqualTo("tiger");
    }

    @Test
    void parsesUrlStyleWithUserInfo() {
        LegacyDbRef ref = LegacyDbSlotParser.parse("oracle://app:pw@10.0.2.7:1521/SVC").orElseThrow();

        assertThat(ref.host()).isEqualTo("10.0.2.7");
        assertThat(ref.port()).isEqualTo(1521);
        assertThat(ref.serviceName()).isEqualTo("SVC");
        assertThat(ref.username()).isEqualTo("app");
        assertThat(ref.password()).isEqualTo("pw");
    }

    @Test
    void parsesOceanBaseUrlWithQueryCredentials() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://10.20.161.98:2881/obfz?connectTimeout=5000&user=obfz@tenant&password=handsome")
                .orElseThrow();

        assertThat(ref.host()).isEqualTo("10.20.161.98");
        assertThat(ref.port()).isEqualTo(2881);
        assertThat(ref.serviceName()).isEqualTo("obfz");
        assertThat(ref.username()).isEqualTo("obfz@tenant");
        assertThat(ref.password()).isEqualTo("handsome");
    }

    @Test
    void decodesUrlStyleQueryCredentialsWithoutSplittingEncodedDelimiters() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://db.example:2881/tenant"
                        + "?USER=app%40oracle_tenant&password=p%2Bss%26word%3D1")
                .orElseThrow();

        assertThat(ref.username()).isEqualTo("app@oracle_tenant");
        assertThat(ref.password()).isEqualTo("p+ss&word=1");
    }

    @Test
    void preservesLiteralPlusInsteadOfApplyingHtmlFormDecoding() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://db.example:2881/tenant"
                        + "?user=app+reader&password=p+ss%2Bword")
                .orElseThrow();

        assertThat(ref.username()).isEqualTo("app+reader");
        assertThat(ref.password()).isEqualTo("p+ss+word");
    }

    @Test
    void parsesQuotedPasswordContainingRawAmpersand() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://db.example:2881/tenant"
                        + "?password='p&ss'&socketTimeout=15000&user=app")
                .orElseThrow();

        assertThat(ref.username()).isEqualTo("app");
        assertThat(ref.password()).isEqualTo("p&ss");
    }

    @Test
    void stripsMatchingOuterQuotesAfterPercentDecoding() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://db.example:2881/tenant"
                        + "?user=app&password=%22p%26ss%22")
                .orElseThrow();

        assertThat(ref.password()).isEqualTo("p&ss");
    }

    @Test
    void malformedUrlEscapeDoesNotAbortParsing() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://db.example:2881/tenant?user=app&password=bad%escape")
                .orElseThrow();

        assertThat(ref.host()).isEqualTo("db.example");
        assertThat(ref.password()).isEqualTo("bad%escape");
    }

    @Test
    void parsesBareHostPortService() {
        LegacyDbRef ref = LegacyDbSlotParser.parse("dbhost:1521/ORCL").orElseThrow();

        assertThat(ref.host()).isEqualTo("dbhost");
        assertThat(ref.port()).isEqualTo(1521);
        assertThat(ref.serviceName()).isEqualTo("ORCL");
        assertThat(ref.username()).isNull();
    }

    @Test
    void blanksMissingPort() {
        LegacyDbRef ref = LegacyDbSlotParser.parse("dbhost").orElseThrow();

        assertThat(ref.host()).isEqualTo("dbhost");
        assertThat(ref.port()).isNull();
        assertThat(ref.serviceName()).isNull();
    }

    @Test
    void parsesPortlessUrlForEngineAwareImporterDefault() {
        LegacyDbRef ref = LegacyDbSlotParser.parse(
                "jdbc:oceanbase:oracle://ob.example/APP?user=app&password=pw").orElseThrow();

        assertThat(ref.host()).isEqualTo("ob.example");
        assertThat(ref.port()).isNull();
        assertThat(ref.serviceName()).isEqualTo("APP");
    }

    @Test
    void blankOrNullIsEmpty() {
        assertThat(LegacyDbSlotParser.parse(null)).isEmpty();
        assertThat(LegacyDbSlotParser.parse("   ")).isEmpty();
    }

    @Test
    void noHostIsEmpty() {
        assertThat(LegacyDbSlotParser.parse("jdbc:oracle:thin:@")).isEmpty();
        assertThat(LegacyDbSlotParser.parse("user/pw@")).isEmpty();
    }
}
