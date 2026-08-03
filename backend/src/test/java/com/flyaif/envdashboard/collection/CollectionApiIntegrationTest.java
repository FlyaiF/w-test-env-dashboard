package com.flyaif.envdashboard.collection;

import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The manual "refresh now" endpoint: a POST collects the Environment on demand and returns its
 * freshly-collected view, and an unknown id yields the shared 404 problem+json contract.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CollectionApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private EnvironmentRepository environments;

    @MockBean
    private MachineAccess machineAccess;

    @BeforeEach
    void clean() {
        environments.deleteAll();
    }

    @Test
    void refreshNowCollectsTheEnvironmentAndReturnsItsFreshView() throws Exception {
        given(machineAccess.httpGet(anyString())).willReturn("4.2.0");

        Environment env = new Environment("ENV-A", null);
        Component app = new Component(ComponentRole.APP);
        app.setVersionProbe(VersionProbeKind.HTTP);
        app.setUrl("http://app/version");
        env.addComponent(app);
        Long id = environments.save(env).getId();

        mockMvc.perform(post("/api/environments/{id}/refresh", id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("ENV-A"))
                .andExpect(jsonPath("$.components[0].collectionStatus").value("OK"))
                .andExpect(jsonPath("$.components[0].version").value("4.2.0"))
                .andExpect(jsonPath("$.components[0].lastCollectedAt").exists());
    }

    @Test
    void refreshUnknownEnvironmentReturns404ProblemJson() throws Exception {
        mockMvc.perform(post("/api/environments/{id}/refresh", 999999L))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Resource not found"))
                .andExpect(jsonPath("$.detail").value("Environment not found: 999999"));
    }
}
