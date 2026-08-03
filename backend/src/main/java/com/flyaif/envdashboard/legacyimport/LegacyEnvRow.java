package com.flyaif.envdashboard.legacyimport;

import java.time.Instant;

/**
 * One raw {@code TENVINFO} row, as read from the legacy database. Field names follow the new domain;
 * the original column appears in the comment. Every text field is nullable because legacy data is
 * dirty — interpreting and blanking those values is the importer's job (PRD §8), not this carrier's.
 */
public record LegacyEnvRow(
        long eNo,             // E_NO
        String name,          // E_NAME
        String businessDb,    // E_YWDB  (业务库)
        String intermediateDb,// E_ZJDB  (中间库)
        String url,           // E_URL
        String version,       // E_VERSION
        Instant updateTime,   // E_UPDATETIME
        String seeUrl,        // E_SEEURL
        String webServerAddr, // E_WEBSERVERADDR  ("host:port&user/password")
        String webLogPath,    // E_WEBLOGPATH
        String memo,          // E_MEMO
        String dbType         // E_DBTYPE
) {
}
