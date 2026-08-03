package com.flyaif.envdashboard.inventory.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

/**
 * Non-secret connection metadata for a {@link Database} — where it lives and the login name. The
 * password is deliberately absent: secret material is encrypted and brokered in slice 06 (ADR-0005).
 */
@Embeddable
public class ConnectionDescriptor {

    @Column(name = "conn_host", length = 255)
    private String host;

    @Column(name = "conn_port")
    private Integer port;

    @Column(name = "conn_service_name", length = 200)
    private String serviceName;

    @Column(name = "conn_username", length = 200)
    private String username;

    protected ConnectionDescriptor() {
        // for JPA
    }

    public ConnectionDescriptor(String host, Integer port, String serviceName, String username) {
        this.host = host;
        this.port = port;
        this.serviceName = serviceName;
        this.username = username;
    }

    public String getHost() {
        return host;
    }

    public Integer getPort() {
        return port;
    }

    public String getServiceName() {
        return serviceName;
    }

    public String getUsername() {
        return username;
    }
}
