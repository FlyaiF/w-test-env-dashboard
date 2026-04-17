package buildinfo

// Populated at build time via -ldflags "-X test-env-dashboard/go_sidecar/buildinfo.Version=..."
var (
	Version   = "dev"
	Commit    = "unknown"
	BuildTime = "unknown"
)
