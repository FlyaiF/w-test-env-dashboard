package com.flyaif.envdashboard.catalog.domain;

/**
 * Whether a {@link Component} is serving right now, judged from its URL. Distinct from
 * {@link CollectionStatus}: a Component can be UP while its version probe fails, and vice versa.
 */
public enum LivenessStatus {
    /** Answered with an HTTP status below 500 (a redirect to a login page counts). */
    UP,
    /** The host answered but the service did not: connection refused, HTTP 5xx, or no response. */
    DOWN,
    /** The host itself could not be reached (timeout, no route, unknown host, invalid URL). */
    UNREACHABLE
}
