use std::path::{Path, PathBuf};

use anyhow::Result;
use zipr_lib::archive::{self, DiffKind, ReplaceOptions};
use zipr_lib::config::Config;
use zipr_lib::path_expr::parse_zip_expr;

// ---------------------------------------------------------------------------
// Models (FRB auto-generates corresponding Dart classes)
// ---------------------------------------------------------------------------

pub struct ArchiveEntry {
    pub expr: String,
    pub size: u64,
    pub compressed_size: u64,
}

pub struct DiffEntry {
    pub path: String,
    /// "added", "removed", or "modified"
    pub kind: String,
    pub content_changed: bool,
    pub metadata_changes: Vec<String>,
}

pub struct DraftSummary {
    pub matched: usize,
    pub unresolved: usize,
    /// The generated TOML spec content
    pub spec_toml: String,
}

pub struct ApplySummary {
    pub replaced: usize,
    pub deleted: usize,
}

// ---------------------------------------------------------------------------
// API functions
// ---------------------------------------------------------------------------

fn default_config() -> Result<Config> {
    Config::load(None)
}

/// List all entries in an archive recursively (including nested archives).
pub fn list_archive(path: String) -> Result<Vec<ArchiveEntry>> {
    let config = default_config()?;
    let items = archive::list_recursive(Path::new(&path), &config)?;
    Ok(items
        .into_iter()
        .map(|e| ArchiveEntry {
            expr: e.expr,
            size: e.size,
            compressed_size: e.compressed_size,
        })
        .collect())
}

/// Extract a single entry from an archive (supports nested paths with `!/`).
/// If `output_path` is provided, writes to that file; otherwise returns bytes.
pub fn extract_entry(zip_expr: String, output_path: String) -> Result<Vec<u8>> {
    let config = default_config()?;
    let parsed = parse_zip_expr(&zip_expr)?;
    let bytes = archive::get(&parsed, &config)?;
    if !output_path.is_empty() {
        std::fs::write(&output_path, &bytes)?;
        Ok(Vec::new())
    } else {
        Ok(bytes)
    }
}

/// Delete an entry from an archive.
pub fn delete_entry(zip_expr: String) -> Result<()> {
    let config = default_config()?;
    let parsed = parse_zip_expr(&zip_expr)?;
    archive::delete(&parsed, &config)
}

/// Replace an entry in an archive with the contents of a source file.
pub fn replace_entry(zip_expr: String, source_path: String) -> Result<()> {
    let config = default_config()?;
    let parsed = parse_zip_expr(&zip_expr)?;
    let opts = ReplaceOptions::default();
    archive::replace(&parsed, Path::new(&source_path), &config, opts)
}

/// Diff two archives recursively and return the list of differences.
pub fn diff_archives(left: String, right: String) -> Result<Vec<DiffEntry>> {
    let config = default_config()?;
    let items = archive::diff_recursive(Path::new(&left), Path::new(&right), &config)?;
    Ok(items
        .into_iter()
        .map(|e| {
            let kind = match e.kind {
                DiffKind::Added => "added",
                DiffKind::Removed => "removed",
                DiffKind::Modified => "modified",
            };
            DiffEntry {
                path: e.path,
                kind: kind.to_string(),
                content_changed: e.content_changed,
                metadata_changes: e.metadata_changes,
            }
        })
        .collect())
}

/// Generate a patch draft TOML spec from a source directory.
/// Returns the summary and the TOML content.
pub fn patch_draft(archive: String, from_dir: String, output: String) -> Result<DraftSummary> {
    let config = default_config()?;
    let output_path = if output.is_empty() {
        PathBuf::from("patch.draft.toml")
    } else {
        PathBuf::from(&output)
    };
    let summary = archive::patch_draft(
        Path::new(&archive),
        Path::new(&from_dir),
        &output_path,
        &config,
    )?;
    let spec_toml = std::fs::read_to_string(&output_path).unwrap_or_default();
    Ok(DraftSummary {
        matched: summary.matched,
        unresolved: summary.unresolved,
        spec_toml,
    })
}

/// Apply a patch spec to an archive.
/// Set `dry_run` to true to preview without modifying.
pub fn patch_apply(archive: String, spec: String, dry_run: bool) -> Result<ApplySummary> {
    let config = default_config()?;
    let summary = archive::patch_apply(
        Path::new(&archive),
        Path::new(&spec),
        dry_run,
        &config,
    )?;
    Ok(ApplySummary {
        replaced: summary.replaced,
        deleted: summary.deleted,
    })
}
