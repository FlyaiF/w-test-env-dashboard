package com.flyaif.envdashboard.legacyimport;

import java.util.Optional;

/**
 * Splits a legacy {@code E_WEBSERVERADDR} string — {@code "host:port&username/password"} — into its
 * parts (ADR-0004, PRD §8). The address half (before {@code &}) carries reachability; the credential
 * half (after {@code &}) carries the SSH login.
 *
 * <p>Tolerant by design, matching the import policy (PRD §8): a usable {@code host} is the only hard
 * requirement. A missing or non-numeric port, or absent credentials, yields a {@link WebServerAddr}
 * with those fields null rather than a failure — the caller blanks them and carries on. Only a value
 * with no recoverable host returns {@link Optional#empty()}, which the caller reports.
 */
public final class WebServerAddrParser {

    private WebServerAddrParser() {
    }

    public static Optional<WebServerAddr> parse(String raw) {
        if (raw == null) {
            return Optional.empty();
        }
        String value = raw.trim();
        if (value.isEmpty()) {
            return Optional.empty();
        }

        // The '&' separates "host:port" from "username/password"; either side may be absent.
        String addrPart = value;
        String credPart = "";
        int amp = value.indexOf('&');
        if (amp >= 0) {
            addrPart = value.substring(0, amp).trim();
            credPart = value.substring(amp + 1).trim();
        }

        String host = null;
        Integer port = null;
        if (!addrPart.isEmpty()) {
            int colon = addrPart.indexOf(':');
            if (colon >= 0) {
                host = addrPart.substring(0, colon).trim();
                port = parsePort(addrPart.substring(colon + 1).trim());
            } else {
                host = addrPart;
            }
        }
        if (host == null || host.isEmpty()) {
            return Optional.empty();
        }

        String username = null;
        String password = null;
        if (!credPart.isEmpty()) {
            int slash = credPart.indexOf('/');
            if (slash >= 0) {
                username = blankToNull(credPart.substring(0, slash).trim());
                password = blankToNull(credPart.substring(slash + 1).trim());
            } else {
                username = blankToNull(credPart);
            }
        }

        return Optional.of(new WebServerAddr(host, port, username, password));
    }

    private static Integer parsePort(String raw) {
        try {
            int port = Integer.parseInt(raw);
            return port > 0 ? port : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String blankToNull(String value) {
        return value == null || value.isEmpty() ? null : value;
    }
}
