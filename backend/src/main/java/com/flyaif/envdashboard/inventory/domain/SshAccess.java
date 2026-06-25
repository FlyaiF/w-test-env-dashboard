package com.flyaif.envdashboard.inventory.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

/**
 * Non-secret SSH access descriptor for a {@link Server} — where and as whom to connect. The password
 * / key is deliberately absent: secret material is encrypted and brokered in slice 06 (ADR-0005).
 */
@Embeddable
public class SshAccess {

    @Column(name = "ssh_host", length = 255)
    private String host;

    @Column(name = "ssh_port")
    private Integer port;

    @Column(name = "ssh_username", length = 200)
    private String username;

    protected SshAccess() {
        // for JPA
    }

    public SshAccess(String host, Integer port, String username) {
        this.host = host;
        this.port = port;
        this.username = username;
    }

    public String getHost() {
        return host;
    }

    public Integer getPort() {
        return port;
    }

    public String getUsername() {
        return username;
    }
}
