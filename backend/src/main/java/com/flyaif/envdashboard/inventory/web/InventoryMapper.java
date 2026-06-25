package com.flyaif.envdashboard.inventory.web;

import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.SshAccess;
import com.flyaif.envdashboard.inventory.web.dto.ConnectionDto;
import com.flyaif.envdashboard.inventory.web.dto.DatabaseDto;
import com.flyaif.envdashboard.inventory.web.dto.ServerDto;
import com.flyaif.envdashboard.inventory.web.dto.SshAccessDto;

/** Maps Resource Inventory aggregates to/from their published DTO contract. */
public final class InventoryMapper {

    private InventoryMapper() {
    }

    public static ServerDto toDto(Server server) {
        return new ServerDto(
                server.getId(),
                server.getHost(),
                server.getOs() == null ? null : server.getOs().name(),
                toDto(server.getSsh()));
    }

    public static SshAccessDto toDto(SshAccess ssh) {
        if (ssh == null) {
            return null;
        }
        return new SshAccessDto(ssh.getHost(), ssh.getPort(), ssh.getUsername());
    }

    public static SshAccess toDomain(SshAccessDto dto) {
        if (dto == null) {
            return null;
        }
        return new SshAccess(dto.host(), dto.port(), dto.username());
    }

    public static DatabaseDto toDto(Database database) {
        return new DatabaseDto(
                database.getId(),
                database.getRole(),
                database.getType() == null ? null : database.getType().name(),
                toDto(database.getConnection()));
    }

    public static ConnectionDto toDto(ConnectionDescriptor connection) {
        if (connection == null) {
            return null;
        }
        return new ConnectionDto(
                connection.getHost(),
                connection.getPort(),
                connection.getServiceName(),
                connection.getUsername());
    }

    public static ConnectionDescriptor toDomain(ConnectionDto dto) {
        if (dto == null) {
            return null;
        }
        return new ConnectionDescriptor(dto.host(), dto.port(), dto.serviceName(), dto.username());
    }
}
