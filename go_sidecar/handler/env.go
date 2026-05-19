package handler

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"test-env-dashboard/go_sidecar/db"
	"test-env-dashboard/go_sidecar/model"
)

const runtimeCollectConcurrency = 4

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, model.ErrorResponse{Error: msg})
}

func writeErrorDetail(w http.ResponseWriter, code int, msg, detail string) {
	writeJSON(w, code, model.ErrorResponse{Error: msg, Detail: detail})
}

// Envs handles GET /api/envs (list) and POST /api/envs (create)
func Envs(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		listEnvs(w, r)
	case http.MethodPost:
		createEnv(w, r)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// EnvByID handles GET/PUT/DELETE /api/envs/{id}
func EnvByID(w http.ResponseWriter, r *http.Request) {
	// Extract ID from path: /api/envs/123
	path := strings.TrimPrefix(r.URL.Path, "/api/envs/")
	id, err := strconv.ParseInt(path, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}

	switch r.Method {
	case http.MethodGet:
		getEnv(w, id)
	case http.MethodPut:
		updateEnv(w, r, id)
	case http.MethodDelete:
		deleteEnv(w, id)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func listEnvs(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	search := q.Get("search")
	page, _ := strconv.Atoi(q.Get("page"))
	pageSize, _ := strconv.Atoi(q.Get("page_size"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 500 {
		pageSize = 100
	}

	list, total, err := db.ListEnvs(search, page, pageSize)
	if err != nil {
		writeErrorDetail(w, http.StatusInternalServerError, "query failed", err.Error())
		return
	}
	if list == nil {
		list = []model.EnvInfo{}
	}

	writeJSON(w, http.StatusOK, model.ListResponse{
		Total:    total,
		Page:     page,
		PageSize: pageSize,
		Data:     list,
	})
}

func getEnv(w http.ResponseWriter, id int64) {
	e, err := db.GetEnv(id)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "environment not found")
		return
	}
	if err != nil {
		writeErrorDetail(w, http.StatusInternalServerError, "query failed", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, model.DataResponse{Data: e})
}

func createEnv(w http.ResponseWriter, r *http.Request) {
	var e model.EnvInfo
	if err := json.NewDecoder(r.Body).Decode(&e); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if e.ENo == 0 {
		writeError(w, http.StatusBadRequest, "e_no is required")
		return
	}

	if err := db.CreateEnv(e); err != nil {
		if strings.Contains(strings.ToUpper(err.Error()), "UNIQUE") ||
			strings.Contains(err.Error(), "ORA-00001") {
			writeError(w, http.StatusConflict, "e_no already exists")
			return
		}
		writeErrorDetail(w, http.StatusInternalServerError, "create failed", err.Error())
		return
	}

	// Fetch back the created record (to get SYSDATE)
	created, err := db.GetEnv(e.ENo)
	if err != nil {
		writeJSON(w, http.StatusCreated, model.DataResponse{Data: e})
		return
	}
	writeJSON(w, http.StatusCreated, model.DataResponse{Data: created})
}

func updateEnv(w http.ResponseWriter, r *http.Request, id int64) {
	var e model.EnvInfo
	if err := json.NewDecoder(r.Body).Decode(&e); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := db.UpdateEnv(id, e); err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "environment not found")
			return
		}
		writeErrorDetail(w, http.StatusInternalServerError, "update failed", err.Error())
		return
	}

	updated, err := db.GetEnv(id)
	if err != nil {
		writeJSON(w, http.StatusOK, model.MessageResponse{Message: "updated"})
		return
	}
	writeJSON(w, http.StatusOK, model.DataResponse{Data: updated})
}

func deleteEnv(w http.ResponseWriter, id int64) {
	if err := db.DeleteEnv(id); err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "environment not found")
			return
		}
		writeErrorDetail(w, http.StatusInternalServerError, "delete failed", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, model.MessageResponse{Message: "deleted"})
}

// CollectPreview handles POST /api/runtime-env/collect-preview.
func CollectPreview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	envs, err := db.ListAllEnvs()
	if err != nil {
		writeErrorDetail(w, http.StatusInternalServerError, "query failed", err.Error())
		return
	}

	results := make([]model.RuntimeEnvCollectionResult, len(envs))
	log.Printf("CollectPreview: collecting %d environments with concurrency=%d", len(envs), runtimeCollectConcurrency)

	jobs := make(chan int)
	var wg sync.WaitGroup
	workerCount := runtimeCollectConcurrency
	if len(envs) < workerCount {
		workerCount = len(envs)
	}
	for worker := 0; worker < workerCount; worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				env := envs[i]
				collectedAt := db.Now()
				dsn := ""
				if env.EYwdb != nil {
					dsn = strings.TrimSpace(*env.EYwdb)
				}
				if dsn == "" {
					results[i] = db.BuildRuntimeSkippedResult(env, "E_YWDB is empty", collectedAt)
					continue
				}

				dbType := ""
				if env.EDbtype != nil {
					dbType = *env.EDbtype
				}
				fresh, err := db.CollectRuntimeEnvInfo(dbType, dsn)
				if err != nil {
					if db.IsUnsupportedRuntimeDBType(err) {
						results[i] = db.BuildRuntimeUnsupportedResult(env, err.Error(), collectedAt)
						continue
					}
					results[i] = db.BuildRuntimeFailedResult(env, err, collectedAt)
					continue
				}
				results[i] = db.BuildRuntimeCollectionResult(env, fresh, collectedAt)
			}
		}()
	}
	for i := range envs {
		jobs <- i
	}
	close(jobs)
	wg.Wait()

	writeJSON(w, http.StatusOK, model.RuntimeCollectPreviewResponse{Data: results})
}

// PublishCollected handles POST /api/runtime-env/publish-collected.
func PublishCollected(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req model.RuntimePublishRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	updated := 0
	skipped := []int64{}
	updatedRows := []model.EnvInfo{}
	for _, item := range req.Items {
		if item.ENo == 0 || (item.SystemVersion == nil && item.BeginTime == nil && item.BeginTimeText == nil) {
			skipped = append(skipped, item.ENo)
			continue
		}
		if err := db.PublishCollectedEnvInfo(item); err != nil {
			if err == sql.ErrNoRows {
				skipped = append(skipped, item.ENo)
				continue
			}
			writeErrorDetail(w, http.StatusInternalServerError, "publish failed", err.Error())
			return
		}
		env, err := db.GetEnv(item.ENo)
		if err != nil {
			writeErrorDetail(w, http.StatusInternalServerError, "publish verify failed", err.Error())
			return
		}
		updatedRows = append(updatedRows, env)
		updated++
	}

	writeJSON(w, http.StatusOK, model.RuntimePublishResponse{
		Updated: updated,
		Skipped: skipped,
		Data:    updatedRows,
	})
}

// TestDB handles POST /api/db/test
func TestDB(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var body struct {
		DSN    string `json:"dsn"`
		Type   string `json:"type"`
		DBType string `json:"db_type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.DSN == "" {
		writeError(w, http.StatusBadRequest, "dsn is required")
		return
	}

	dbType := body.DBType
	if dbType == "" {
		dbType = body.Type
	}
	if dbType == "" {
		dbType = db.RuntimeDBOracle
	}
	if err := db.TestRuntimeConnection(dbType, body.DSN); err != nil {
		writeErrorDetail(w, http.StatusBadRequest, "connection failed", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, model.MessageResponse{Message: "connection successful"})
}

// DBTypes handles GET /api/db/types.
func DBTypes(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	writeJSON(w, http.StatusOK, model.DBTypesResponse{Data: db.RuntimeDBTypes()})
}
