package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.web.InventoryMapper;
import com.flyaif.envdashboard.inventory.web.dto.DatabaseDto;
import com.flyaif.envdashboard.inventory.web.dto.DatabaseRequest;
import com.flyaif.envdashboard.shared.ResourceInUseException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * CRUD for the shared {@link Database} aggregate. Deletion is guarded: a Database still used by a
 * Component is refused with a conflict rather than silently cascaded (ADR-0003).
 */
@Service
@Transactional
public class DatabaseService {

    private final DatabaseRepository databases;
    private final ResourceUsage usage;

    public DatabaseService(DatabaseRepository databases, ResourceUsage usage) {
        this.databases = databases;
        this.usage = usage;
    }

    @Transactional(readOnly = true)
    public List<DatabaseDto> list() {
        return databases.findAll().stream().map(InventoryMapper::toDto).toList();
    }

    @Transactional(readOnly = true)
    public DatabaseDto get(Long id) {
        return InventoryMapper.toDto(require(id));
    }

    public DatabaseDto create(DatabaseRequest request) {
        Database database = new Database(
                request.role(), request.type(), InventoryMapper.toDomain(request.connection()));
        return InventoryMapper.toDto(databases.save(database));
    }

    public DatabaseDto update(Long id, DatabaseRequest request) {
        Database database = require(id);
        database.setRole(request.role());
        database.setType(request.type());
        database.setConnection(InventoryMapper.toDomain(request.connection()));
        return InventoryMapper.toDto(database);
    }

    public void delete(Long id) {
        Database database = require(id);
        if (usage.isDatabaseInUse(id)) {
            throw new ResourceInUseException(
                    "Database " + id + " is still used by one or more Components");
        }
        databases.delete(database);
    }

    private Database require(Long id) {
        return databases.findById(id).orElseThrow(() -> new DatabaseNotFoundException(id));
    }
}
