package com.flyaif.envdashboard.legacyimport;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Masks credentials in a legacy composite string before it is echoed into the {@link ImportReport}.
 * The report is the slice's deliverable and is logged, so the careful never-persist-secrets stance
 * (ADR-0005) must extend to never-log-secrets: passwords live after {@code &} in an SSH address, in
 * the {@code user/password@} or {@code user:password@} userinfo of a DSN/URL, and in a
 * {@code password=} query parameter. Host, port, and service — the parts a human needs to fix a
 * row — are preserved.
 */
final class LegacyValueRedactor {

    private static final Pattern PASSWORD_QUERY_PARAMETER =
            Pattern.compile("(?i)(?:^|[?&])password=");

    private LegacyValueRedactor() {
    }

    static String redact(String raw) {
        if (raw == null) {
            return null;
        }

        String base = raw;
        String query = "";
        int q = raw.indexOf('?');
        if (q >= 0) {
            base = raw.substring(0, q);
            query = raw.substring(q);
        }

        // SSH composite "host:port&user/password": credentials follow the '&'.
        int amp = base.indexOf('&');
        if (amp >= 0) {
            base = base.substring(0, amp + 1) + "***";
        }

        // DSN/URL userinfo "user/password@" or "user:password@", possibly after a scheme or thin: prefix.
        int at = base.indexOf('@');
        if (at >= 0) {
            int start = 0;
            int scheme = base.lastIndexOf("://", at);
            if (scheme >= 0) {
                start = scheme + 3;
            } else {
                int thin = base.toLowerCase().lastIndexOf("thin:", at);
                if (thin >= 0) {
                    start = thin + "thin:".length();
                }
            }
            base = base.substring(0, start) + "***" + base.substring(at);
        }

        // Conservatively mask the remainder once password= begins. Quoted OceanBase passwords may
        // legally contain '&', so stopping at the next ampersand could leak the secret tail into logs.
        Matcher passwordParameter = PASSWORD_QUERY_PARAMETER.matcher(query);
        if (passwordParameter.find()) {
            query = query.substring(0, passwordParameter.end()) + "***";
        }
        return base + query;
    }
}
