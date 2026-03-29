package handler

import (
	"encoding/json"
	"net/http"
	"test-env-dashboard/go_sidecar/db"
	"test-env-dashboard/go_sidecar/model"
)

func Health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	connected := true
	if err := db.Pool().Ping(); err != nil {
		connected = false
	}

	status := "ok"
	code := http.StatusOK
	if !connected {
		status = "error"
		code = http.StatusServiceUnavailable
	}

	w.WriteHeader(code)
	json.NewEncoder(w).Encode(model.HealthResponse{
		Status:      status,
		DbConnected: connected,
	})
}
