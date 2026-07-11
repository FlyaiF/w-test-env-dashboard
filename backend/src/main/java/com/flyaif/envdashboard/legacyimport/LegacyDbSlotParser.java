package com.flyaif.envdashboard.legacyimport;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Parses a legacy database slot ({@code E_YWDB} / {@code E_ZJDB}) connection string into a
 * {@link LegacyDbRef}. Legacy data mixes several shapes, mirroring the Go sidecar's own normaliser:
 *
 * <ul>
 *   <li>Oracle thin with creds — {@code jdbc:oracle:thin:user/password@host:port/service}</li>
 *   <li>Oracle thin, no creds — {@code jdbc:oracle:thin:@host:port:sid}</li>
 *   <li>Plain creds — {@code user/password@host:port/service}</li>
 *   <li>URL style — {@code oracle://...}, {@code jdbc:oceanbase:oracle://host:port/db?user=..&password=..}</li>
 *   <li>Bare address — {@code host:port/service}, {@code host:port:sid}, {@code host:port}, {@code host}</li>
 * </ul>
 *
 * <p>Tolerant per the import policy (PRD §8): only a recoverable {@code host} is required; a missing
 * port, service, or credentials yields nulls the caller blanks. A value with no host returns
 * {@link Optional#empty()} so the caller can report it.
 */
public final class LegacyDbSlotParser {

    private static final Pattern ORACLE_THIN_PREFIX =
            Pattern.compile("(?i)^jdbc:oracle:thin:");
    /** {@code user/password@address} — credentials separated from the address by '@'. */
    private static final Pattern PLAIN_CREDS =
            Pattern.compile("^([^/\\s]+)/([^@\\s]*)@(.*)$");
    private LegacyDbSlotParser() {
    }

    public static Optional<LegacyDbRef> parse(String raw) {
        if (raw == null) {
            return Optional.empty();
        }
        String value = raw.trim();
        if (value.isEmpty()) {
            return Optional.empty();
        }

        int scheme = value.indexOf("://");
        if (scheme >= 0) {
            return parseUrl(value, scheme);
        }

        // Strip an Oracle thin prefix so the remainder is "user/password@addr" or "@addr" or bare.
        String rest = ORACLE_THIN_PREFIX.matcher(value).replaceFirst("");

        String username = null;
        String password = null;
        String address = rest;
        if (rest.startsWith("@")) {
            address = rest.substring(1);
        } else {
            Matcher creds = PLAIN_CREDS.matcher(rest);
            if (creds.matches()) {
                username = blankToNull(creds.group(1));
                password = blankToNull(creds.group(2));
                address = creds.group(3);
            }
        }

        return buildFromAddress(address, username, password);
    }

    private static Optional<LegacyDbRef> parseUrl(String value, int schemeIdx) {
        String rest = value.substring(schemeIdx + 3);

        String query = "";
        int q = rest.indexOf('?');
        if (q >= 0) {
            query = rest.substring(q + 1);
            rest = rest.substring(0, q);
        }

        String username = null;
        String password = null;
        int at = rest.indexOf('@');
        if (at >= 0) {
            String userinfo = rest.substring(0, at);
            rest = rest.substring(at + 1);
            int colon = userinfo.indexOf(':');
            if (colon >= 0) {
                username = blankToNull(decodeUrlComponent(userinfo.substring(0, colon)));
                password = blankToNull(decodeUrlComponent(userinfo.substring(colon + 1)));
            } else {
                username = blankToNull(decodeUrlComponent(userinfo));
            }
        }
        if (!query.isEmpty()) {
            Map<String, String> parameters = parseQuery(query);
            if (username == null) {
                username = blankToNull(parameters.get("user"));
            }
            if (password == null) {
                password = blankToNull(parameters.get("password"));
            }
        }

        return buildFromAddress(rest, username, password);
    }

    /**
     * Parse only the credential parameters we consume. Parameter separators inside quoted JDBC values
     * are data, not delimiters; percent-decoding happens only after tokenization. Malformed escapes are
     * tolerated so one dirty legacy value cannot abort the entire import.
     */
    private static Map<String, String> parseQuery(String query) {
        Map<String, String> parameters = new LinkedHashMap<>();
        for (String part : splitQueryParameters(query)) {
            int equals = part.indexOf('=');
            String rawKey = equals < 0 ? part : part.substring(0, equals);
            String rawValue = equals < 0 ? "" : part.substring(equals + 1);
            String key = decodeUrlComponent(rawKey).toLowerCase(Locale.ROOT);
            if ((key.equals("user") || key.equals("password")) && !parameters.containsKey(key)) {
                parameters.put(key, decodeQueryValue(rawValue));
            }
        }
        return parameters;
    }

    private static List<String> splitQueryParameters(String query) {
        List<String> parameters = new ArrayList<>();
        int start = 0;
        char quote = 0;
        boolean escaped = false;
        for (int i = 0; i < query.length(); i++) {
            char current = query.charAt(i);
            if (quote != 0) {
                if (escaped) {
                    escaped = false;
                } else if (current == '\\') {
                    escaped = true;
                } else if (current == quote) {
                    quote = 0;
                }
            } else if (current == '\'' || current == '"') {
                quote = current;
            } else if (current == '&') {
                parameters.add(query.substring(start, i));
                start = i + 1;
            }
        }
        parameters.add(query.substring(start));
        return parameters;
    }

    private static String decodeQueryValue(String rawValue) {
        String decoded = decodeUrlComponent(rawValue).trim();
        if (decoded.length() >= 2) {
            char first = decoded.charAt(0);
            char last = decoded.charAt(decoded.length() - 1);
            if ((first == '\'' || first == '"') && first == last) {
                return decoded.substring(1, decoded.length() - 1);
            }
        }
        return decoded;
    }

    private static String decodeUrlComponent(String value) {
        try {
            // JDBC query strings treat a raw '+' literally; URLDecoder implements HTML form rules
            // where '+' means space. Protect raw plus signs while retaining normal percent-decoding.
            return URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException malformedEscape) {
            // Keep the recoverable raw value. Import policy is tolerant: report/retain dirty-but-usable
            // data instead of turning a malformed percent escape into a whole-run failure.
            return value;
        }
    }

    /** Parse the bare {@code host:port[/service]} / {@code host:port:sid} address tail. */
    private static Optional<LegacyDbRef> buildFromAddress(String address, String username, String password) {
        String addr = address == null ? "" : address.trim();
        while (addr.startsWith("/") || addr.startsWith("@")) {
            addr = addr.substring(1);
        }
        if (addr.isEmpty()) {
            return Optional.empty();
        }

        String hostPort = addr;
        String service = null;
        int slash = addr.indexOf('/');
        if (slash >= 0) {
            hostPort = addr.substring(0, slash);
            service = blankToNull(addr.substring(slash + 1).trim());
        }

        String host;
        Integer port = null;
        String[] parts = hostPort.split(":");
        host = parts.length > 0 ? parts[0].trim() : "";
        if (parts.length >= 2) {
            port = parsePort(parts[1].trim());
        }
        // Oracle SID form "host:port:sid" carries the service name in the third colon-segment.
        if (parts.length >= 3 && service == null) {
            service = blankToNull(parts[2].trim());
        }

        if (host.isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(new LegacyDbRef(host, port, service, username, password));
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
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
