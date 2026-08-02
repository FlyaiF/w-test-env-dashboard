package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.web.EnvironmentController;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
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
 * The service is mocked so this isolates the controller from persistence
 * ({@link EnvironmentRepositoryTest} covers the JPA side).
 */
@WebMvcTest(EnvironmentController.class)
class EnvironmentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private EnvironmentService service;

    private static ComponentDto gateway() {
        return new ComponentDto(1L, "GATEWAY", "1.2.3", Instant.parse("2026-01-02T03:04:05Z"),
                "/var/log/gateway.log", 8080, "https", "https://gw.example/health",
                5L, List.of(7L, 8L), null, null, null, null);
    }

    private static EnvironmentDto envA() {
        return new EnvironmentDto(1L, "ENV-A", "first env", "https://see.example/acm/env/1",
                List.of(gateway(), new ComponentDto(2L, "APP", null, null, null, null, null, null,
                        null, List.of(), null, null, null, null)));
    }

    @Test
    void listReturnsEnvironmentsEachWithTheirComponents() throws Exception {
        EnvironmentDto envB = new EnvironmentDto(2L, "ENV-B", null, null,
                List.of(new ComponentDto(3L, "UI", null, null, null, null, null, null,
                        null, List.of(), null, null, null, null)));
        given(service.listEnvironments()).willReturn(List.of(envA(), envB));

        mockMvc.perform(get("/api/environments"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[?(@.name=='ENV-A')].components[*].role",
                        hasItems("GATEWAY", "APP")));
    }

    @Test
    void getByIdReturnsOneEnvironmentWithGlossaryFieldNamesAndLinks() throws Exception {
        given(service.getEnvironment(1L)).willReturn(envA());

        mockMvc.perform(get("/api/environments/{id}", 1L))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("ENV-A"))
                .andExpect(jsonPath("$.memo").value("first env"))
                .andExpect(jsonPath("$.seeUrl").value("https://see.example/acm/env/1"))
                .andExpect(jsonPath("$.components", hasSize(2)))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].version").value("1.2.3"))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].versionUpdatedAt")
                        .value("2026-01-02T03:04:05Z"))
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].serverId").value(5))
                // Definite path here: a filter expression would wrap the array, breaking hasItems.
                .andExpect(jsonPath("$.components[0].databaseIds").value(hasItems(7, 8)))
                // Collection fields present in the contract but null until slice 05.
                .andExpect(jsonPath("$.components[?(@.role=='GATEWAY')].collectionStatus").value((Object) null));
    }

    @Test
    void getByIdReturnsProblemJson404ForUnknownId() throws Exception {
        given(service.getEnvironment(999999L)).willThrow(new EnvironmentNotFoundException(999999L));

        mockMvc.perform(get("/api/environments/{id}", 999999L))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.title").value("Resource not found"))
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.detail").value("Environment not found: 999999"));
    }
}
