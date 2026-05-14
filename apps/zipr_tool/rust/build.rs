use std::path::Path;
use std::process::Command;

fn main() {
    let zipr_dir = Path::new("../../../zipr");

    println!("cargo:rerun-if-changed={}", zipr_dir.join("Cargo.toml").display());
    println!("cargo:rerun-if-changed=../../../.git/modules/zipr/HEAD");
    println!("cargo:rerun-if-env-changed=ZIPR_GIT_REV");
    println!("cargo:rerun-if-env-changed=ZIPR_VERSION");

    let version = std::env::var("ZIPR_VERSION")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| read_zipr_version(zipr_dir));
    println!("cargo:rustc-env=ZIPR_VERSION={version}");

    let rev = std::env::var("ZIPR_GIT_REV")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| zipr_git_rev(zipr_dir));
    println!("cargo:rustc-env=ZIPR_GIT_REV={rev}");
}

fn read_zipr_version(dir: &Path) -> String {
    let manifest = match std::fs::read_to_string(dir.join("Cargo.toml")) {
        Ok(s) => s,
        Err(_) => return "unknown".to_string(),
    };
    for line in manifest.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("version") {
            if let Some(eq) = rest.find('=') {
                let value = rest[eq + 1..].trim().trim_matches('"');
                if !value.is_empty() {
                    return value.to_string();
                }
            }
        }
    }
    "unknown".to_string()
}

fn zipr_git_rev(dir: &Path) -> String {
    let out = Command::new("git")
        .args(["rev-parse", "--short=12", "HEAD"])
        .current_dir(dir)
        .output();
    if let Ok(out) = out {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return s;
            }
        }
    }
    "unknown".to_string()
}
