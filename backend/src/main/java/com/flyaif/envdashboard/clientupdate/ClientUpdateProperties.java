package com.flyaif.envdashboard.clientupdate;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration for desktop-client self-update distribution. Release zips are copied into
 * {@code dir} by the operator (scripts/publish_update.sh); the backend only ever reads it. A blank
 * dir disables the feature: the latest-version endpoint answers 204 and clients stay quiet.
 */
@ConfigurationProperties(prefix = "envdashboard.client-updates")
public class ClientUpdateProperties {

    /** Directory holding {@code env_viewer-<version>-<platform>.zip} files. Blank = disabled. */
    private String dir = "";

    public String getDir() {
        return dir;
    }

    public void setDir(String dir) {
        this.dir = dir;
    }
}
