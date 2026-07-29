package com.flyaif.envdashboard.catalog.domain;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * One deployable part of an {@link Environment} (gateway, UI, app, private-protocol service).
 * Carries a role, a single live {@link #version} (or blank) with its Version update time, a log location,
 * reachability (listen port / protocol / URL), and Collection bookkeeping that stays null until
 * the collector lands (slice 05). Not an aggregate root — only ever reached through its Environment.
 */
@Entity
@Table(name = "component")
public class Component {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "component_seq_gen")
    @SequenceGenerator(name = "component_seq_gen", sequenceName = "component_seq", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "environment_id", nullable = false)
    private Environment environment;

    /** The Server this Component runs on, referenced by ID (ADR-0003). Null if not yet linked. */
    @Column(name = "server_id")
    private Long serverId;

    /** The Databases this Component uses, referenced by ID (0..N, ADR-0003). */
    @ElementCollection
    @CollectionTable(name = "component_database", joinColumns = @JoinColumn(name = "component_id"))
    @Column(name = "database_id")
    private Set<Long> databaseIds = new LinkedHashSet<>();

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 40)
    private ComponentRole role;

    /** The live Version string, or blank/null if unknown. Maps the {@code app_version} column. */
    @Column(name = "app_version", length = 200)
    private String version;

    @Column(name = "version_updated_at")
    private Instant versionUpdatedAt;

    @Column(name = "log_location", length = 500)
    private String logLocation;

    @Column(name = "listen_port")
    private Integer listenPort;

    @Column(name = "protocol", length = 40)
    private String protocol;

    @Column(name = "url", length = 500)
    private String url;

    @Enumerated(EnumType.STRING)
    @Column(name = "version_probe", length = 40)
    private VersionProbeKind versionProbe;

    @Enumerated(EnumType.STRING)
    @Column(name = "collection_status", length = 20)
    private CollectionStatus collectionStatus;

    /** Why the last collection went non-OK (probe detail); null after a successful collection. */
    @Column(name = "collection_detail", length = 2000)
    private String collectionDetail;

    @Column(name = "last_collected_at")
    private Instant lastCollectedAt;

    protected Component() {
        // for JPA
    }

    public Component(ComponentRole role) {
        this.role = role;
    }

    public Long getId() {
        return id;
    }

    /** Set by {@link Environment#addComponent} only — the aggregate root owns the link. */
    void setEnvironment(Environment environment) {
        this.environment = environment;
    }

    public Environment getEnvironment() {
        return environment;
    }

    public Long getServerId() {
        return serverId;
    }

    /** Link this Component to the Server it runs on (by ID), or null to unlink. */
    public void setServerId(Long serverId) {
        this.serverId = serverId;
    }

    public Set<Long> getDatabaseIds() {
        return Collections.unmodifiableSet(databaseIds);
    }

    /** Replace the set of Databases this Component uses (by ID). */
    public void setDatabaseIds(Set<Long> databaseIds) {
        this.databaseIds = new LinkedHashSet<>(databaseIds);
    }

    public ComponentRole getRole() {
        return role;
    }

    public void setRole(ComponentRole role) {
        this.role = role;
    }

    public String getVersion() {
        return version;
    }

    public void setVersion(String version) {
        this.version = version;
    }

    public Instant getVersionUpdatedAt() {
        return versionUpdatedAt;
    }

    public void setVersionUpdatedAt(Instant versionUpdatedAt) {
        this.versionUpdatedAt = versionUpdatedAt;
    }

    public String getLogLocation() {
        return logLocation;
    }

    public void setLogLocation(String logLocation) {
        this.logLocation = logLocation;
    }

    public Integer getListenPort() {
        return listenPort;
    }

    public void setListenPort(Integer listenPort) {
        this.listenPort = listenPort;
    }

    public String getProtocol() {
        return protocol;
    }

    public void setProtocol(String protocol) {
        this.protocol = protocol;
    }

    public String getUrl() {
        return url;
    }

    public void setUrl(String url) {
        this.url = url;
    }

    public VersionProbeKind getVersionProbe() {
        return versionProbe;
    }

    public void setVersionProbe(VersionProbeKind versionProbe) {
        this.versionProbe = versionProbe;
    }

    public CollectionStatus getCollectionStatus() {
        return collectionStatus;
    }

    public void setCollectionStatus(CollectionStatus collectionStatus) {
        this.collectionStatus = collectionStatus;
    }

    public String getCollectionDetail() {
        return collectionDetail;
    }

    public void setCollectionDetail(String collectionDetail) {
        this.collectionDetail = collectionDetail;
    }

    public Instant getLastCollectedAt() {
        return lastCollectedAt;
    }

    public void setLastCollectedAt(Instant lastCollectedAt) {
        this.lastCollectedAt = lastCollectedAt;
    }
}
