package com.flyaif.envdashboard.collection.liveness;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;

/**
 * Bounds for the liveness check. Kept short: the sweep runs every minute and checks every Component
 * in parallel, so one dead host costs at most {@code connectTimeout + requestTimeout}. The sweep's
 * cadence and on/off switch are read by {@link LivenessScheduler} from the same prefix.
 */
@ConfigurationProperties(prefix = "envdashboard.liveness")
public class LivenessProperties {

    /** Maximum time to open the TCP connection; past it the host counts as unreachable. */
    private Duration connectTimeout = Duration.ofSeconds(3);

    /** Maximum time from sending the request to receiving response headers. */
    private Duration requestTimeout = Duration.ofSeconds(5);

    public Duration getConnectTimeout() {
        return connectTimeout;
    }

    public void setConnectTimeout(Duration connectTimeout) {
        this.connectTimeout = connectTimeout;
    }

    public Duration getRequestTimeout() {
        return requestTimeout;
    }

    public void setRequestTimeout(Duration requestTimeout) {
        this.requestTimeout = requestTimeout;
    }
}
