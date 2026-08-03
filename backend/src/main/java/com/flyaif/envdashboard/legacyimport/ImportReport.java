package com.flyaif.envdashboard.legacyimport;

import java.util.ArrayList;
import java.util.List;

/**
 * The outcome of an import run, and the slice's core deliverable for trust: nothing is ever silently
 * discarded (PRD §8). Every blanked field, every dropped row, and every judgement call is recorded
 * with the legacy {@code E_NO} and a reason for human follow-up, alongside summary counts. Doubles as
 * the dry-run preview — the same report is produced whether or not rows are actually written.
 */
public class ImportReport {

    /** A legacy row that could not fit the new shape and was skipped (never silently dropped). */
    public record DroppedRow(long eNo, String reason) {
    }

    /** A field left blank because the source value was dirty but the row was otherwise usable. */
    public record BlankedField(long eNo, String field, String reason) {
    }

    /** A judgement call worth a human's eye (e.g. a defaulted OS or a duplicate credential). */
    public record Note(long eNo, String message) {
    }

    private final boolean dryRun;

    private final List<Long> importedEnvironments = new ArrayList<>();
    private final List<DroppedRow> droppedRows = new ArrayList<>();
    private final List<BlankedField> blankedFields = new ArrayList<>();
    private final List<Note> notes = new ArrayList<>();

    private int componentsCreated;
    private int serversCreated;
    private int serversReused;
    private int databasesCreated;
    private int databasesReused;
    private int credentialsSeen;

    public ImportReport(boolean dryRun) {
        this.dryRun = dryRun;
    }

    public void importedEnvironment(long eNo) {
        importedEnvironments.add(eNo);
    }

    public void droppedRow(long eNo, String reason) {
        droppedRows.add(new DroppedRow(eNo, reason));
    }

    public void blankedField(long eNo, String field, String reason) {
        blankedFields.add(new BlankedField(eNo, field, reason));
    }

    public void note(long eNo, String message) {
        notes.add(new Note(eNo, message));
    }

    public void componentCreated() {
        componentsCreated++;
    }

    public void serverCreated() {
        serversCreated++;
    }

    public void serverReused() {
        serversReused++;
    }

    public void databaseCreated() {
        databasesCreated++;
    }

    public void databaseReused() {
        databasesReused++;
    }

    public void credentialSeen() {
        credentialsSeen++;
    }

    public boolean isDryRun() {
        return dryRun;
    }

    public List<Long> getImportedEnvironments() {
        return List.copyOf(importedEnvironments);
    }

    public List<DroppedRow> getDroppedRows() {
        return List.copyOf(droppedRows);
    }

    public List<BlankedField> getBlankedFields() {
        return List.copyOf(blankedFields);
    }

    public List<Note> getNotes() {
        return List.copyOf(notes);
    }

    public int getComponentsCreated() {
        return componentsCreated;
    }

    public int getServersCreated() {
        return serversCreated;
    }

    public int getServersReused() {
        return serversReused;
    }

    public int getDatabasesCreated() {
        return databasesCreated;
    }

    public int getDatabasesReused() {
        return databasesReused;
    }

    public int getCredentialsSeen() {
        return credentialsSeen;
    }

    /** A human-readable, multi-section rendering for the migration report log. */
    public String render() {
        StringBuilder sb = new StringBuilder();
        sb.append("TENVINFO import report");
        sb.append(dryRun ? " (DRY RUN — nothing written)\n" : "\n");
        sb.append("======================================================\n");
        sb.append("Environments imported : ").append(importedEnvironments.size()).append('\n');
        sb.append("Components created     : ").append(componentsCreated).append('\n');
        sb.append("Servers   created/reused : ").append(serversCreated).append(" / ").append(serversReused).append('\n');
        sb.append("Databases created/reused : ").append(databasesCreated).append(" / ").append(databasesReused).append('\n');
        sb.append("Rows dropped          : ").append(droppedRows.size()).append('\n');
        sb.append("Fields blanked        : ").append(blankedFields.size()).append('\n');
        if (credentialsSeen > 0) {
            sb.append("Legacy credential fields seen : ").append(credentialsSeen).append('\n');
            sb.append(dryRun
                    ? "Secret handling       : dry run; no secrets stored\n"
                    : "Secret handling       : secrets encrypted in the access broker when present; first value wins for shared resources\n");
        }

        if (!droppedRows.isEmpty()) {
            sb.append("\nDropped rows (could not fit the new shape):\n");
            for (DroppedRow d : droppedRows) {
                sb.append("  E_NO ").append(d.eNo()).append(": ").append(d.reason()).append('\n');
            }
        }
        if (!blankedFields.isEmpty()) {
            sb.append("\nBlanked fields (dirty source, left empty for manual fix):\n");
            for (BlankedField b : blankedFields) {
                sb.append("  E_NO ").append(b.eNo()).append(" ").append(b.field())
                        .append(": ").append(b.reason()).append('\n');
            }
        }
        if (!notes.isEmpty()) {
            sb.append("\nNotes (judgement calls):\n");
            for (Note n : notes) {
                sb.append("  E_NO ").append(n.eNo()).append(": ").append(n.message()).append('\n');
            }
        }
        return sb.toString();
    }
}
