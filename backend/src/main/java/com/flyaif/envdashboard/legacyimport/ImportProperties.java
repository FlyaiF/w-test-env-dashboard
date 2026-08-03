package com.flyaif.envdashboard.legacyimport;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration for the one-time {@code TENVINFO} import (active only under the {@code import} profile).
 * Where the legacy database lives, which table to read, and — defaulting to {@code true} for safety —
 * whether this is a dry run that previews without writing.
 */
@ConfigurationProperties(prefix = "envdashboard.import")
public class ImportProperties {

    /** Preview only — parse and report but write nothing. Defaults to true so a bare run is harmless. */
    private boolean dryRun = true;

    /** Legacy table to read. */
    private String table = "TENVINFO";

    private final Legacy legacy = new Legacy();

    public boolean isDryRun() {
        return dryRun;
    }

    public void setDryRun(boolean dryRun) {
        this.dryRun = dryRun;
    }

    public String getTable() {
        return table;
    }

    public void setTable(String table) {
        this.table = table;
    }

    public Legacy getLegacy() {
        return legacy;
    }

    /** JDBC coordinates for the legacy database (the old Oracle holding {@code TENVINFO}). */
    public static class Legacy {
        private String url;
        private String username;
        private String password;

        public String getUrl() {
            return url;
        }

        public void setUrl(String url) {
            this.url = url;
        }

        public String getUsername() {
            return username;
        }

        public void setUsername(String username) {
            this.username = username;
        }

        public String getPassword() {
            return password;
        }

        public void setPassword(String password) {
            this.password = password;
        }
    }
}
