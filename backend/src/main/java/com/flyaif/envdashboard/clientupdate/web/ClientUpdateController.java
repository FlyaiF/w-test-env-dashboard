package com.flyaif.envdashboard.clientupdate.web;

import com.flyaif.envdashboard.clientupdate.ClientRelease;
import com.flyaif.envdashboard.clientupdate.ClientUpdateService;
import com.flyaif.envdashboard.clientupdate.web.dto.ClientUpdateDto;
import com.flyaif.envdashboard.shared.NotFoundException;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Desktop-client self-update API. {@code latest} is the startup poll (204 = nothing to offer, so
 * quiet-by-default clients need no error handling for the disabled case); {@code download} streams
 * the exact version the client saw in {@code latest}, so its SHA-256 check stays meaningful even if
 * a newer zip lands between the two calls.
 */
@RestController
@RequestMapping("/api/client-updates/env_viewer")
public class ClientUpdateController {

    private final ClientUpdateService updates;

    public ClientUpdateController(ClientUpdateService updates) {
        this.updates = updates;
    }

    @GetMapping("/latest")
    public ResponseEntity<ClientUpdateDto> latest(@RequestParam String platform) {
        return updates.latest(platform)
                .map(r -> ResponseEntity.ok(ClientUpdateDto.from(r)))
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @GetMapping("/download")
    public ResponseEntity<Resource> download(
            @RequestParam String platform, @RequestParam String version) {
        ClientRelease release = updates.find(platform, version)
                .orElseThrow(() -> new NotFoundException(
                        "env_viewer " + version + " (" + platform + ") 不再提供下载"));
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .contentLength(release.sizeBytes())
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"" + release.zip().getFileName() + "\"")
                .body(new FileSystemResource(release.zip()));
    }
}
