package com.flyaif.envdashboard.inventory;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
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

import java.util.Map;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Full-stack Resource Inventory tests: CRUD, linking a Component to shared resources, delete
 * protection (409), and both reverse lookups — against H2 (Oracle mode).
 */
@SpringBootTest
@AutoConfigureMockMvc
class InventoryApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper json;

    @Autowired
    private ServerRepository servers;

    @Autowired
    private DatabaseRepository databases;

    @Autowired
    private EnvironmentRepository environments;

    @BeforeEach
    void clean() {
        environments.deleteAll();
        servers.deleteAll();
        databases.deleteAll();
    }

    @Test
    void createsAndReadsBackAServer() throws Exception {
        String body = json.writeValueAsString(Map.of(
                "host", "host-01",
                "os", "LINUX",
                "ssh", Map.of("host", "10.0.0.1", "port", 22, "username", "deploy")));

        mockMvc.perform(post("/api/servers").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").exists())
                .andExpect(jsonPath("$.host").value("host-01"))
                .andExpect(jsonPath("$.os").value("LINUX"))
                .andExpect(jsonPath("$.ssh.username").value("deploy"));

        mockMvc.perform(get("/api/servers"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void rejectsServerCreateWithMissingHost() throws Exception {
        String body = json.writeValueAsString(Map.of("os", "LINUX"));

        mockMvc.perform(post("/api/servers").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    @Test
    void updatesADatabase() throws Exception {
        Database db = databases.save(new Database("business", DatabaseType.ORACLE, null));

        String body = json.writeValueAsString(Map.of(
                "role", "config",
                "type", "DAMENG",
                "connection", Map.of("host", "10.0.0.9", "port", 5236, "serviceName", "CFG", "username", "cfg")));

        mockMvc.perform(put("/api/databases/{id}", db.getId())
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.role").value("config"))
                .andExpect(jsonPath("$.type").value("DAMENG"))
                .andExpect(jsonPath("$.connection.serviceName").value("CFG"));
    }

    @Test
    void getUnknownServerReturns404ProblemJson() throws Exception {
        mockMvc.perform(get("/api/servers/{id}", 999999L))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Resource not found"));
    }

    @Test
    void linksComponentToServerAndDatabasesThenSurfacesViaReverseLookups() throws Exception {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));
        Database db1 = databases.save(new Database("business", DatabaseType.ORACLE, null));
        Database db2 = databases.save(new Database("config", DatabaseType.DAMENG, null));

        Environment env = new Environment("ENV-A", null);
        env.addComponent(new Component(ComponentRole.APP));
        Environment saved = environments.save(env);
        Long componentId = saved.getComponents().get(0).getId();

        String links = json.writeValueAsString(Map.of(
                "serverId", server.getId(),
                "databaseIds", java.util.List.of(db1.getId(), db2.getId())));

        mockMvc.perform(put("/api/components/{id}/links", componentId)
                        .contentType(MediaType.APPLICATION_JSON).content(links))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.serverId").value(server.getId().intValue()))
                .andExpect(jsonPath("$.databaseIds", hasSize(2)));

        // Reverse lookup: which Environments run on this Server?
        mockMvc.perform(get("/api/servers/{id}/environments", server.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name").value("ENV-A"));

        // Reverse lookup: which Environments use this Database?
        mockMvc.perform(get("/api/databases/{id}/environments", db1.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name").value("ENV-A"));
    }

    @Test
    void deletingAReferencedServerIsRefusedWith409() throws Exception {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));
        Environment env = new Environment("ENV-A", null);
        Component app = new Component(ComponentRole.APP);
        app.setServerId(server.getId());
        env.addComponent(app);
        environments.save(env);

        mockMvc.perform(delete("/api/servers/{id}", server.getId()))
                .andExpect(status().isConflict())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Resource in use"));
    }

    @Test
    void deletingAReferencedDatabaseIsRefusedWith409() throws Exception {
        Database db = databases.save(new Database("business", DatabaseType.ORACLE, null));
        Environment env = new Environment("ENV-A", null);
        Component app = new Component(ComponentRole.APP);
        app.setDatabaseIds(java.util.Set.of(db.getId()));
        env.addComponent(app);
        environments.save(env);

        mockMvc.perform(delete("/api/databases/{id}", db.getId()))
                .andExpect(status().isConflict())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Resource in use"));
    }

    @Test
    void deletingAnUnreferencedDatabaseSucceeds() throws Exception {
        Database db = databases.save(new Database("business", DatabaseType.ORACLE, null));

        mockMvc.perform(delete("/api/databases/{id}", db.getId()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/databases/{id}", db.getId()))
                .andExpect(status().isNotFound());
    }

    @Test
    void linkingToNonexistentDatabaseReturns404() throws Exception {
        Environment env = new Environment("ENV-A", null);
        env.addComponent(new Component(ComponentRole.APP));
        Long componentId = environments.save(env).getComponents().get(0).getId();

        String links = json.writeValueAsString(Map.of("databaseIds", java.util.List.of(999999)));

        mockMvc.perform(put("/api/components/{id}/links", componentId)
                        .contentType(MediaType.APPLICATION_JSON).content(links))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.detail").value("Database not found: 999999"));
    }
}
