package handler

import (
	"encoding/json"
	"net/http"
	"runtime"
	"test-env-dashboard/go_sidecar/buildinfo"
	"test-env-dashboard/go_sidecar/model"
)

func Version(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(model.VersionResponse{
		Version:   buildinfo.Version,
		Commit:    buildinfo.Commit,
		BuildTime: buildinfo.BuildTime,
		GoVersion: runtime.Version(),
		Platform:  runtime.GOOS + "/" + runtime.GOARCH,
	})
}
