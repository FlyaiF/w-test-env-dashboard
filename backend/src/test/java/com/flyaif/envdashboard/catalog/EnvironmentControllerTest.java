package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.web.EnvironmentController;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;

import static org.hamcrest.Matchers.hasItems;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Web-layer test for the read endpoints: serialization, glossary field names, and the 404 contract.
 * The service is mocked so this isolates the controller/mapper from persistence
 * ({@link EnvironmentRepositoryTest} covers the JPA side).
 */
@WebMvcTest(EnvironmentController.class)
class EnvironmentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private EnvironmentService service;

    private static Environment envA() {
        Environment env = new Environment("ENV-A", "first env");
        Component gateway = new Component(ComponentRole.GATEWAY);
        gateway.setVersion("1.2.3");
        gateway.setDeployTime(Instant.parse("2026-01-02T03:04:05Z"));
        gateway.setLogLocation("/var/log/gateway.log");
        gateway.setListenPort(8080);
        gateway.setProtocol("https");
        gateway.setUrl("https://gw.example/health");
        env.addComponent(gateway);
        env.addComponent(new Component(ComponentRole.APP));
        return env;
    }

    @Test
    void listReturnsEnvironmentsEachWithTheirComponents() throws Exception {
        Environment envB = new Environment("ENV-B", null);
        envB.addComponent(new Component(ComponentRole.UI));
        given(service.listEnvironments()).willReturn(List.of(envA(), envB));

        mockMvc.perform(get("/api/environments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[?(@.name=='ENV-A')].components[*].role",
                        hasItems("GATEWAY", "APP")));
    }

    @Test
    void getByIdReturnsOneEnvironmentWithGlossaryFieldNames() throws Exception {
        given(service.getEnvironment(1L)).willReturn(envA());

        mockMvc.perform(get("/api/environments/{id}", 1L))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("ENV-A"))
                .andExpect(jsonPath("$.memo").value("first env"))
                .andExpect(jsonPath("$.components", hasSize(2)))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].version").value("1.2.3"))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].deployTime")
                        .value("2026-01-02T03:04:05Z"))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].listenPort").value(8080))
                // Collection fields present in the contract but null until slice 05.
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].collectionStatus").value((Object) null));
    }

    @Test
    void getByIdReturnsProblemJson404ForUnknownId() throws Exception {
        given(service.getEnvironment(999999L)).willThrow(new EnvironmentNotFoundException(999999L));

        mockMvc.perform(get("/api/environments/{id}", 999999L))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Environment not found"))
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.detail").value("Environment not found: 999999"));
    }
}
