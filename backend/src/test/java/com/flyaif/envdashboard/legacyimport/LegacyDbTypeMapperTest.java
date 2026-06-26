package com.flyaif.envdashboard.legacyimport;

import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;

class LegacyDbTypeMapperTest {

    @ParameterizedTest
    @CsvSource({
            "0,ORACLE", "ora,ORACLE", "Oracle,ORACLE",
            "2,DAMENG", "dm,DAMENG", "DAMENG,DAMENG", "dm8,DAMENG",
            "1,OCEANBASE", "ob,OCEANBASE", "oceanbase,OCEANBASE", "OceanBase_Oracle,OCEANBASE",
    })
    void mapsKnownCodesAndNames(String raw, DatabaseType expected) {
        assertThat(LegacyDbTypeMapper.map(raw)).isEqualTo(expected);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void defaultsBlankToOracle(String raw) {
        assertThat(LegacyDbTypeMapper.map(raw)).isEqualTo(DatabaseType.ORACLE);
    }

    @ParameterizedTest
    @ValueSource(strings = {"postgres", "mysql", "wat"})
    void mapsUnknownToOther(String raw) {
        assertThat(LegacyDbTypeMapper.map(raw)).isEqualTo(DatabaseType.OTHER);
    }
}
