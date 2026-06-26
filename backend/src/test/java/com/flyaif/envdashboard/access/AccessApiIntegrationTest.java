package com.flyaif.envdashboard.access;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.ServerOs;
import com.flyaif.envdashboard.inventory.domain.SshAccess;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Full-stack Access Brokering tests (ADR-0005): secrets are stored encrypted at rest, brokered back on
 * demand with a connection descriptor, and the write/read paths 404 / 400 correctly — against H2.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AccessApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper json;

    @Autowired
    private ServerRepository servers;

    @Autowired
    private DatabaseRepository databases;

    @Autowired
    private ServerSecretRepository serverSecrets;

    @Autowired
    private DatabaseSecretRepository databaseSecrets;

    @BeforeEach
    void clean() {
        serverSecrets.deleteAll();
        databaseSecrets.deleteAll();
        servers.deleteAll();
        databases.deleteAll();
    }

    @Test
    void storesServerSecretEncryptedAndBrokersItBack() throws Exception {
        Server server = servers.save(
                new Server("host-01", ServerOs.LINUX, new SshAccess("10.0.0.1", 22, "deploy")));

        mockMvc.perform(put("/api/servers/{id}/secret", server.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("secret", "s3cr3t"))))
                .andExpect(status().isNoContent());

        // Encrypted at rest: the persisted column is not the plaintext.
        String atRest = serverSecrets.findById(server.getId()).orElseThrow().getSecretEnc();
        assertThat(atRest).isNotEqualTo("s3cr3t");
        assertThat(atRest).doesNotContain("s3cr3t");

        // Brokered back on demand: descriptor + decrypted secret.
        mockMvc.perform(get("/api/servers/{id}/credentials", server.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.serverId").value(server.getId().intValue()))
                .andExpect(jsonPath("$.host").value("10.0.0.1"))
                .andExpect(jsonPath("$.port").value(22))
                .andExpect(jsonPath("$.username").value("deploy"))
                .andExpect(jsonPath("$.secret").value("s3cr3t"));
    }

    @Test
    void updatingAServerSecretReplacesIt() throws Exception {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));

        putSecret("/api/servers/" + server.getId() + "/secret", "old");
        putSecret("/api/servers/" + server.getId() + "/secret", "new");

        assertThat(serverSecrets.count()).isEqualTo(1); // upsert, not a second row
        mockMvc.perform(get("/api/servers/{id}/credentials", server.getId()))
                .andExpect(jsonPath("$.secret").value("new"));
    }

    @Test
    void storesDatabaseSecretEncryptedAndBrokersItWithJdbcUrl() throws Exception {
        Database db = databases.save(new Database("business", DatabaseType.ORACLE,
                new ConnectionDescriptor("10.0.2.5", 1521, "ORCL", "app")));

        putSecret("/api/databases/" + db.getId() + "/secret", "db-pw");

        String atRest = databaseSecrets.findById(db.getId()).orElseThrow().getSecretEnc();
        assertThat(atRest).doesNotContain("db-pw");

        mockMvc.perform(get("/api/databases/{id}/credentials", db.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.databaseId").value(db.getId().intValue()))
                .andExpect(jsonPath("$.type").value("ORACLE"))
                .andExpect(jsonPath("$.host").value("10.0.2.5"))
                .andExpect(jsonPath("$.username").value("app"))
                .andExpect(jsonPath("$.jdbcUrl").value("jdbc:oracle:thin:@//10.0.2.5:1521/ORCL"))
                .andExpect(jsonPath("$.secret").value("db-pw"));
    }

    @Test
    void brokersDescriptorWithNullSecretWhenNoneStored() throws Exception {
        Server server = servers.save(
                new Server("host-01", ServerOs.LINUX, new SshAccess("10.0.0.1", 22, "deploy")));

        mockMvc.perform(get("/api/servers/{id}/credentials", server.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("deploy"))
                .andExpect(jsonPath("$.secret").doesNotExist());
    }

    @Test
    void settingASecretForAnUnknownServerReturns404() throws Exception {
        mockMvc.perform(put("/api/servers/{id}/secret", 999999L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("secret", "x"))))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Resource not found"));
    }

    @Test
    void brokeringCredentialsForAnUnknownDatabaseReturns404() throws Exception {
        mockMvc.perform(get("/api/databases/{id}/credentials", 999999L))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.title").value("Resource not found"));
    }

    @Test
    void rejectsABlankSecret() throws Exception {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));

        mockMvc.perform(put("/api/servers/{id}/secret", server.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("secret", " "))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    @Test
    void rejectsAnOversizeSecret() throws Exception {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));

        mockMvc.perform(put("/api/servers/{id}/secret", server.getId())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("secret", "x".repeat(1025)))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    private void putSecret(String path, String secret) throws Exception {
        mockMvc.perform(put(path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("secret", secret))))
                .andExpect(status().isNoContent());
    }
}
