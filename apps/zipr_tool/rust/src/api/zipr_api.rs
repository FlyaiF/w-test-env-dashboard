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
    /// Structured unresolved entries for UI resolution
    pub unresolved_entries: Vec<UnresolvedEntry>,
}

pub struct UnresolvedEntry {
    pub source: String,
    pub reason: String,
    pub candidates: Vec<String>,
}

pub struct Resolution {
    pub source: String,
    /// "pick" or "ignore"
    pub action: String,
    /// The chosen target path; only used when action == "pick"
    pub chosen_target: String,
}

pub struct ApplySummary {
    pub replaced: usize,
    pub deleted: usize,
}

pub struct RustBuildInfo {
    pub zipr_version: String,
    pub zipr_git_rev: String,
}

// ---------------------------------------------------------------------------
// API functions
// ---------------------------------------------------------------------------

fn default_config() -> Result<Config> {
    Config::load(None)
}

/// Build info for the embedded zipr_lib Rust crate.
pub fn rust_build_info() -> RustBuildInfo {
    RustBuildInfo {
        zipr_version: env!("ZIPR_VERSION").to_string(),
        zipr_git_rev: env!("ZIPR_GIT_REV").to_string(),
    }
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
    let spec = zipr_lib::patch_spec::PatchSpec::read_from_file_lenient(&output_path)?;
    let unresolved_entries = spec
        .unresolved
        .iter()
        .map(|u| UnresolvedEntry {
            source: u.source.clone(),
            reason: u.reason.clone(),
            candidates: u.candidates.clone(),
        })
        .collect();
    Ok(DraftSummary {
        matched: summary.matched,
        unresolved: summary.unresolved,
        spec_toml,
        unresolved_entries,
    })
}

/// Apply a patch spec to an archive.
/// Set `dry_run` to true to preview without modifying.
pub fn patch_apply(archive: String, spec: String, dry_run: bool) -> Result<ApplySummary> {
    let config = default_config()?;
    let summary = archive::patch_apply(Path::new(&archive), Path::new(&spec), dry_run, &config)?;
    Ok(ApplySummary {
        replaced: summary.replaced,
        deleted: summary.deleted,
    })
}

/// Read a patch spec file leniently (no validation) and return its summary.
/// Used for reloading after external edits.
pub fn read_patch_spec(spec_path: String) -> Result<DraftSummary> {
    let spec = zipr_lib::patch_spec::PatchSpec::read_from_file_lenient(Path::new(&spec_path))?;
    let spec_toml = std::fs::read_to_string(&spec_path).unwrap_or_default();
    let unresolved_entries = spec
        .unresolved
        .iter()
        .map(|u| UnresolvedEntry {
            source: u.source.clone(),
            reason: u.reason.clone(),
            candidates: u.candidates.clone(),
        })
        .collect();
    Ok(DraftSummary {
        matched: spec.entry.len(),
        unresolved: spec.unresolved.len(),
        spec_toml,
        unresolved_entries,
    })
}

/// Apply resolutions to unresolved entries in a patch spec.
/// Each resolution either picks a target ("pick") or ignores the entry ("ignore").
/// Returns the updated summary after writing the modified spec back to disk.
pub fn patch_resolve(spec_path: String, resolutions: Vec<Resolution>) -> Result<DraftSummary> {
    let path = Path::new(&spec_path);
    let mut spec = zipr_lib::patch_spec::PatchSpec::read_from_file_lenient(path)?;
    for r in &resolutions {
        match r.action.as_str() {
            "pick" => spec.resolve_entry(&r.source, Some(&r.chosen_target)),
            _ => spec.resolve_entry(&r.source, None),
        }
    }
    spec.write_to_file(path)?;
    let spec_toml = std::fs::read_to_string(&spec_path).unwrap_or_default();
    let unresolved_entries = spec
        .unresolved
        .iter()
        .map(|u| UnresolvedEntry {
            source: u.source.clone(),
            reason: u.reason.clone(),
            candidates: u.candidates.clone(),
        })
        .collect();
    Ok(DraftSummary {
        matched: spec.entry.len(),
        unresolved: spec.unresolved.len(),
        spec_toml,
        unresolved_entries,
    })
}
