package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.web.InventoryMapper;
import com.flyaif.envdashboard.inventory.web.dto.ServerDto;
import com.flyaif.envdashboard.inventory.web.dto.ServerRequest;
import com.flyaif.envdashboard.shared.ResourceInUseException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * CRUD for the shared {@link Server} aggregate. Deletion is guarded: a Server still referenced by a
 * Component is refused with a conflict rather than silently cascaded (ADR-0003).
 */
@Service
@Transactional
public class ServerService {

    private final ServerRepository servers;
    private final ResourceUsage usage;
    private final SecretPresence secretPresence;

    public ServerService(ServerRepository servers, ResourceUsage usage, SecretPresence secretPresence) {
        this.servers = servers;
        this.usage = usage;
        this.secretPresence = secretPresence;
    }

    @Transactional(readOnly = true)
    public List<ServerDto> list() {
        var withSecret = secretPresence.serverIdsWithSecret();
        return servers.findAll().stream()
                .map(server -> InventoryMapper.toDto(server, withSecret.contains(server.getId())))
                .toList();
    }

    @Transactional(readOnly = true)
    public ServerDto get(Long id) {
        return InventoryMapper.toDto(require(id), secretPresence.serverHasSecret(id));
    }

    public ServerDto create(ServerRequest request) {
        Server server = new Server(request.host(), request.os(), InventoryMapper.toDomain(request.ssh()));
        return InventoryMapper.toDto(servers.save(server), false);
    }

    public ServerDto update(Long id, ServerRequest request) {
        Server server = require(id);
        server.setHost(request.host());
        server.setOs(request.os());
        server.setSsh(InventoryMapper.toDomain(request.ssh()));
        return InventoryMapper.toDto(server, secretPresence.serverHasSecret(id));
    }

    public void delete(Long id) {
        Server server = require(id);
        if (usage.isServerInUse(id)) {
            throw new ResourceInUseException(
                    "Server " + id + " is still referenced by one or more Components");
        }
        servers.delete(server);
    }

    private Server require(Long id) {
        return servers.findById(id).orElseThrow(() -> new ServerNotFoundException(id));
    }
}
