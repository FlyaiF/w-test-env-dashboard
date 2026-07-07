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
 * A database instance that Components connect to. A <em>shared</em> aggregate with its own lifecycle
 * (ADR-0003): not necessarily dedicated to one Environment, so Components reference it by ID and it
 * is never owned. Mapped to {@code database_resource} because {@code database} is a reserved word.
 */
@Entity
@Table(name = "database_resource")
public class Database {

    /**
     * Well-known {@link #role} for an environment's business database (业务库, legacy E_YWDB). The role
     * is free text, but this value is load-bearing: the db-query version probe reads the version and
     * 版本更新时间 from the linked Database carrying it (issue 08). The TENVINFO importer stamps it.
     */
    public static final String BUSINESS_ROLE = "business";

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "database_seq_gen")
    @SequenceGenerator(name = "database_seq_gen", sequenceName = "database_seq", allocationSize = 1)
    private Long id;

    @Column(name = "role", length = 100)
    private String role;

    @Enumerated(EnumType.STRING)
    @Column(name = "db_type", nullable = false, length = 40)
    private DatabaseType type;

    @Embedded
    private ConnectionDescriptor connection;

    protected Database() {
        // for JPA
    }

    public Database(String role, DatabaseType type, ConnectionDescriptor connection) {
        this.role = role;
        this.type = type;
        this.connection = connection;
    }

    public Long getId() {
        return id;
    }

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public DatabaseType getType() {
        return type;
    }

    public void setType(DatabaseType type) {
        this.type = type;
    }

    public ConnectionDescriptor getConnection() {
        return connection;
    }

    public void setConnection(ConnectionDescriptor connection) {
        this.connection = connection;
    }
}
