package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
import org.springframework.stereotype.Component;

/**
 * Obtains a Component's version from its HTTP endpoint (e.g. a {@code /health} or {@code /version} URL).
 * The trimmed response body is taken as the live version; the probe leaves the Version update time to a richer
 * probe rather than guessing. Registered for {@link VersionProbeKind#HTTP}.
 */
@Component
public class HttpVersionProbe implements VersionProbe {

    private final MachineAccess machineAccess;

    public HttpVersionProbe(MachineAccess machineAccess) {
        this.machineAccess = machineAccess;
    }

    @Override
    public VersionProbeKind kind() {
        return VersionProbeKind.HTTP;
    }

    @Override
    public ProbeResult probe(ProbeContext context) {
        String url = context.component().getUrl();
        if (url == null || url.isBlank()) {
            return ProbeResult.failed("HTTP probe needs a Component url, but none is set");
        }
        String body = machineAccess.httpGet(url);
        String version = body == null ? "" : body.strip();
        if (version.isEmpty()) {
            return ProbeResult.failed("HTTP probe got an empty response from " + url);
        }
        return ProbeResult.ok(version, null);
    }
}
