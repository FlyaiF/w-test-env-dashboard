package com.flyaif.envdashboard.clientupdate;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Client self-update API against a real (temp) updates directory: newest-version selection, SHA-256
 * and notes in the metadata, exact-version download, and the 204/404 edges of the directory-drop
 * publishing contract.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ClientUpdateApiIntegrationTest {

    @TempDir
    static Path updatesDir;

    @DynamicPropertySource
    static void updatesProperty(DynamicPropertyRegistry registry) {
        registry.add("envdashboard.client-updates.dir", () -> updatesDir.toString());
    }

    @Autowired
    private MockMvc mockMvc;

    private Path publish(String name, byte[] content) throws IOException {
        return Files.write(updatesDir.resolve(name), content);
    }

    private static String sha256(byte[] content) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(content));
    }

    @Test
    void latestPicksHighestVersionPerPlatformWithChecksumAndNotes() throws Exception {
        byte[] newer = "macos-120".getBytes(StandardCharsets.UTF_8);
        publish("env_viewer-1.2.0-macos.zip", newer);
        publish("env_viewer-1.10.0-windows.zip", "win-1100".getBytes(StandardCharsets.UTF_8));
        publish("env_viewer-1.9.0-windows.zip", "win-190".getBytes(StandardCharsets.UTF_8));
        publish("env_viewer-1.2.0.notes.md", "修复日志查看".getBytes(StandardCharsets.UTF_8));

        mockMvc.perform(get("/api/client-updates/env_viewer/latest").param("platform", "macos"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value("1.2.0"))
                .andExpect(jsonPath("$.platform").value("macos"))
                .andExpect(jsonPath("$.fileName").value("env_viewer-1.2.0-macos.zip"))
                .andExpect(jsonPath("$.sizeBytes").value(newer.length))
                .andExpect(jsonPath("$.sha256").value(sha256(newer)))
                .andExpect(jsonPath("$.notes").value("修复日志查看"));

        // 1.10 orders above 1.9 numerically, not lexically; its notes file is absent -> null.
        mockMvc.perform(get("/api/client-updates/env_viewer/latest").param("platform", "windows"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value("1.10.0"))
                .andExpect(jsonPath("$.notes").doesNotExist());
    }

    @Test
    void downloadStreamsTheExactRequestedVersion() throws Exception {
        byte[] bytes = "old-but-requested".getBytes(StandardCharsets.UTF_8);
        publish("env_viewer-1.9.0-windows.zip", bytes);

        mockMvc.perform(get("/api/client-updates/env_viewer/download")
                        .param("platform", "windows")
                        .param("version", "1.9.0"))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Disposition",
                        "attachment; filename=\"env_viewer-1.9.0-windows.zip\""))
                .andExpect(content().bytes(bytes));
    }

    @Test
    void unknownDownloadIs404AndUnknownPlatformIs204() throws Exception {
        mockMvc.perform(get("/api/client-updates/env_viewer/download")
                        .param("platform", "windows")
                        .param("version", "0.0.1"))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/client-updates/env_viewer/latest").param("platform", "linux"))
                .andExpect(status().isNoContent());
    }
}
