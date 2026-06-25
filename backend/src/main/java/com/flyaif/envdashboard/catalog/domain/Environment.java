package com.flyaif.envdashboard.catalog.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * One test deployment of the system — the aggregate root. It owns its {@link Component}s; they are
 * created, persisted, and removed only through the Environment (cascade + orphan removal), matching
 * the {@code ON DELETE CASCADE} declared in the schema.
 */
@Entity
@Table(name = "environment")
public class Environment {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "environment_seq_gen")
    @SequenceGenerator(name = "environment_seq_gen", sequenceName = "environment_seq", allocationSize = 1)
    private Long id;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "memo", length = 1000)
    private String memo;

    @OneToMany(mappedBy = "environment", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Component> components = new ArrayList<>();

    protected Environment() {
        // for JPA
    }

    public Environment(String name, String memo) {
        this.name = name;
        this.memo = memo;
    }

    /** Add a Component to this Environment, keeping both sides of the link consistent. */
    public void addComponent(Component component) {
        components.add(component);
        component.setEnvironment(this);
    }

    public Long getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getMemo() {
        return memo;
    }

    public void setMemo(String memo) {
        this.memo = memo;
    }

    public List<Component> getComponents() {
        return Collections.unmodifiableList(components);
    }
}
