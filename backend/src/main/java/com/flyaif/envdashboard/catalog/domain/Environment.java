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
import java.util.Optional;

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

    /** Link to this environment's console in SEE, the company's environment-management platform. */
    @Column(name = "see_url", length = 500)
    private String seeUrl;

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

    /**
     * Remove an owned Component. Orphan removal deletes it on flush; no shared Server/Database it
     * referenced is touched (ADR-0003) — those are referenced by ID and owned elsewhere.
     */
    public void removeComponent(Component component) {
        components.remove(component);
    }

    /** The owned Component with this id, or empty if no Component under this Environment matches. */
    public Optional<Component> findComponent(Long componentId) {
        return components.stream()
                .filter(c -> c.getId() != null && c.getId().equals(componentId))
                .findFirst();
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

    public String getSeeUrl() {
        return seeUrl;
    }

    public void setSeeUrl(String seeUrl) {
        this.seeUrl = seeUrl;
    }

    public List<Component> getComponents() {
        return Collections.unmodifiableList(components);
    }
}
