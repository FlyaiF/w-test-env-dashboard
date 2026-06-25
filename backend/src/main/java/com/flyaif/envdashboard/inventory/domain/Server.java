package com.flyaif.envdashboard.inventory.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;

/**
 * A physical or virtual machine that Components run on. A <em>shared</em> aggregate with its own
 * lifecycle (ADR-0003): one Server can host Components from several Environments, so Components
 * reference it by ID and it is never owned by an Environment.
 */
@Entity
@Table(name = "server")
public class Server {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "server_seq_gen")
    @SequenceGenerator(name = "server_seq_gen", sequenceName = "server_seq", allocationSize = 1)
    private Long id;

    @Column(name = "host", nullable = false, length = 255)
    private String host;

    @Enumerated(EnumType.STRING)
    @Column(name = "os", nullable = false, length = 20)
    private ServerOs os;

    @Embedded
    private SshAccess ssh;

    protected Server() {
        // for JPA
    }

    public Server(String host, ServerOs os, SshAccess ssh) {
        this.host = host;
        this.os = os;
        this.ssh = ssh;
    }

    public Long getId() {
        return id;
    }

    public String getHost() {
        return host;
    }

    public void setHost(String host) {
        this.host = host;
    }

    public ServerOs getOs() {
        return os;
    }

    public void setOs(ServerOs os) {
        this.os = os;
    }

    public SshAccess getSsh() {
        return ssh;
    }

    public void setSsh(SshAccess ssh) {
        this.ssh = ssh;
    }
}
