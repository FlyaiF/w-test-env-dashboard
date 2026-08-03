package com.flyaif.envdashboard.collection.machine;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;

/**
 * Bounded JDBC settings for live version Collection. The defaults match the legacy OceanBase helper
 * while remaining configurable per deployment for slower networks.
 */
@ConfigurationProperties(prefix = "envdashboard.collection.jdbc")
public class JdbcAccessProperties {

    /** Maximum time allowed to establish a probe connection. */
    private Duration loginTimeout = Duration.ofSeconds(5);

    /** Maximum time a version SQL statement may execute. */
    private Duration queryTimeout = Duration.ofSeconds(10);

    /** Maximum time a connected driver may block waiting for network data. */
    private Duration readTimeout = Duration.ofSeconds(15);

    public Duration getLoginTimeout() {
        return loginTimeout;
    }

    public void setLoginTimeout(Duration loginTimeout) {
        this.loginTimeout = loginTimeout;
    }

    public Duration getQueryTimeout() {
        return queryTimeout;
    }

    public void setQueryTimeout(Duration queryTimeout) {
        this.queryTimeout = queryTimeout;
    }

    public Duration getReadTimeout() {
        return readTimeout;
    }

    public void setReadTimeout(Duration readTimeout) {
        this.readTimeout = readTimeout;
    }
}
