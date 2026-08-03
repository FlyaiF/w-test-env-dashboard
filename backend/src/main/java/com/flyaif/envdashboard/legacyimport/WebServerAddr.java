package com.flyaif.envdashboard.legacyimport;

/**
 * The parsed pieces of a legacy {@code E_WEBSERVERADDR} value, whose on-disk shape is the composite
 * string {@code "host:port&username/password"} (ADR-0004, PRD §8). Only {@link #host} is guaranteed
 * present; the rest are null when the legacy string omitted or mangled them — the importer leaves the
 * corresponding new-schema field blank rather than inventing a value.
 *
 * <p>The {@link #password} is captured for completeness but has no home in the current schema: secret
 * material is encrypted and brokered in slice 06 (ADR-0005), so the importer does not persist it.
 */
public record WebServerAddr(String host, Integer port, String username, String password) {
}
