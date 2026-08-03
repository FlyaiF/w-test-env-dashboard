package com.flyaif.envdashboard.catalog;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.ServerOs;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Full-stack Environment Catalog write-path tests (slice 03): create / update / delete of
 * Environments and their Components, validation, and — crucially — the cascade boundary: deleting an
 * Environment removes its owned Components but never touches a shared Server/Database (ADR-0003).
 */
@SpringBootTest
@AutoConfigureMockMvc
class CatalogWriteApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper json;

    @Autowired
    private EnvironmentRepository environments;

    @Autowired
    private ComponentRepository components;

    @Autowired
    private ServerRepository servers;

    @Autowired
    private DatabaseRepository databases;

    @BeforeEach
    void clean() {
        environments.deleteAll();
        servers.deleteAll();
        databases.deleteAll();
    }

    @Test
    void createsAnEnvironmentWithInlineComponentsAndAssignsIds() throws Exception {
        String body = json.writeValueAsString(Map.of(
                "name", "ENV-A",
                "memo", "first env",
                "seeUrl", "  https://see.example/acm/env/a  ",
                "components", List.of(
                        Map.of("role", "GATEWAY", "version", "1.2.3",
                                "versionUpdatedAt", "2026-01-02T03:04:05Z",
                                "logLocation", "/var/log/gw.log", "listenPort", 8080,
                                "protocol", "https", "url", "https://gw/health",
                                "versionProbe", "HTTP"),
                        Map.of("role", "APP"))));

        mockMvc.perform(post("/api/environments")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").exists())
                .andExpect(jsonPath("$.name").value("ENV-A"))
                .andExpect(jsonPath("$.memo").value("first env"))
                // Lenient normalization: trimmed, never scheme-checked.
                .andExpect(jsonPath("$.seeUrl").value("https://see.example/acm/env/a"))
                .andExpect(jsonPath("$.components", hasSize(2)))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].id").exists())
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].version").value("1.2.3"))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].versionProbe").value("HTTP"));

        assertThat(environments.findAll()).hasSize(1);
    }

    @Test
    void createsAnEnvironmentWithNoComponents() throws Exception {
        String body = json.writeValueAsString(Map.of("name", "ENV-EMPTY"));

        mockMvc.perform(post("/api/environments")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.components", hasSize(0)));
    }

    @Test
    void rejectsEnvironmentCreateWithBlankName() throws Exception {
        String body = json.writeValueAsString(Map.of("name", "   "));

        mockMvc.perform(post("/api/environments")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    @Test
    void rejectsInlineComponentWithMissingRole() throws Exception {
        String body = json.writeValueAsString(Map.of(
                "name", "ENV-A",
                "components", List.of(Map.of("version", "1.0"))));

        mockMvc.perform(post("/api/environments")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    @Test
    void updatesEnvironmentNameAndMemoWithoutDisturbingComponents() throws Exception {
        Environment env = new Environment("OLD", "old memo");
        env.addComponent(new Component(ComponentRole.APP));
        Long id = environments.save(env).getId();

        String body = json.writeValueAsString(Map.of("name", "NEW", "memo", "new memo"));

        mockMvc.perform(put("/api/environments/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("NEW"))
                .andExpect(jsonPath("$.memo").value("new memo"))
                .andExpect(jsonPath("$.components", hasSize(1)));
    }

    @Test
    void updateSetsAndClearsTheSeeUrl() throws Exception {
        Environment env = new Environment("ENV-A", null);
        env.setSeeUrl("https://see.example/acm/env/old");
        Long id = environments.save(env).getId();

        String cleared = json.writeValueAsString(Map.of("name", "ENV-A", "seeUrl", "   "));

        // Blank clears the link rather than storing whitespace.
        mockMvc.perform(put("/api/environments/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON).content(cleared))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.seeUrl").value((Object) null));

        String set = json.writeValueAsString(
                Map.of("name", "ENV-A", "seeUrl", "https://see.example/acm/env/new"));

        mockMvc.perform(put("/api/environments/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON).content(set))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.seeUrl").value("https://see.example/acm/env/new"));
    }

    @Test
    void updatingUnknownEnvironmentReturns404() throws Exception {
        String body = json.writeValueAsString(Map.of("name", "NEW"));

        mockMvc.perform(put("/api/environments/{id}", 999999L)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.detail").value("Environment not found: 999999"));
    }

    @Test
    void addsAComponentToAnExistingEnvironment() throws Exception {
        Long id = environments.save(new Environment("ENV-A", null)).getId();

        String body = json.writeValueAsString(Map.of(
                "role", "UI", "version", "2.0.0", "listenPort", 9000));

        mockMvc.perform(post("/api/environments/{id}/components", id)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").exists())
                .andExpect(jsonPath("$.role").value("UI"))
                .andExpect(jsonPath("$.version").value("2.0.0"))
                .andExpect(jsonPath("$.listenPort").value(9000));

        Environment reloaded = environments.findById(id).orElseThrow();
        assertThat(reloaded.getComponents()).hasSize(1);
    }

    @Test
    void updatesAComponentInPlace() throws Exception {
        Environment env = new Environment("ENV-A", null);
        env.addComponent(new Component(ComponentRole.APP));
        Environment saved = environments.save(env);
        Long envId = saved.getId();
        Long componentId = saved.getComponents().get(0).getId();

        String body = json.writeValueAsString(Map.of(
                "role", "GATEWAY", "version", "3.3.3", "protocol", "https"));

        mockMvc.perform(put("/api/environments/{envId}/components/{cid}", envId, componentId)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(componentId.intValue()))
                .andExpect(jsonPath("$.role").value("GATEWAY"))
                .andExpect(jsonPath("$.version").value("3.3.3"));
    }

    @Test
    void deletesASingleComponentFromAnEnvironment() throws Exception {
        Environment env = new Environment("ENV-A", null);
        env.addComponent(new Component(ComponentRole.APP));
        env.addComponent(new Component(ComponentRole.UI));
        Environment saved = environments.save(env);
        Long envId = saved.getId();
        Long componentId = saved.getComponents().get(0).getId();

        mockMvc.perform(delete("/api/environments/{envId}/components/{cid}", envId, componentId))
                .andExpect(status().isNoContent());

        assertThat(environments.findById(envId).orElseThrow().getComponents()).hasSize(1);
        assertThat(components.findById(componentId)).isEmpty();
    }

    @Test
    void componentOperationsScopedToTheWrongEnvironmentReturn404() throws Exception {
        Environment a = new Environment("ENV-A", null);
        a.addComponent(new Component(ComponentRole.APP));
        Environment savedA = environments.save(a);
        Long componentInA = savedA.getComponents().get(0).getId();

        Long envB = environments.save(new Environment("ENV-B", null)).getId();

        // The component exists, but not under ENV-B.
        mockMvc.perform(delete("/api/environments/{envId}/components/{cid}", envB, componentInA))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    @Test
    void deletingAnEnvironmentCascadesToComponentsButNotSharedResources() throws Exception {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));
        Database db = databases.save(new Database("business", DatabaseType.ORACLE, null));

        Environment env = new Environment("ENV-A", null);
        Component app = new Component(ComponentRole.APP);
        app.setServerId(server.getId());
        app.setDatabaseIds(Set.of(db.getId()));
        env.addComponent(app);
        Environment saved = environments.save(env);
        Long envId = saved.getId();
        Long componentId = saved.getComponents().get(0).getId();

        mockMvc.perform(delete("/api/environments/{id}", envId))
                .andExpect(status().isNoContent());

        // Environment and its Component are gone...
        assertThat(environments.findById(envId)).isEmpty();
        assertThat(components.findById(componentId)).isEmpty();
        // ...but the shared Server and Database it referenced are untouched (ADR-0003).
        assertThat(servers.findById(server.getId())).isPresent();
        assertThat(databases.findById(db.getId())).isPresent();
    }

    @Test
    void deletingAnUnknownEnvironmentReturns404() throws Exception {
        mockMvc.perform(delete("/api/environments/{id}", 999999L))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }
}
