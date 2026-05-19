package model

import "time"

type EnvInfo struct {
	ENo            int64      `json:"e_no"`
	EName          *string    `json:"e_name"`
	EYwdb          *string    `json:"e_ywdb"`
	EZjdb          *string    `json:"e_zjdb"`
	EUrl           *string    `json:"e_url"`
	EVersion       *string    `json:"e_version"`
	EUpdatetime    *time.Time `json:"e_updatetime"`
	ESeeurl        *string    `json:"e_seeurl"`
	EWebserveraddr *string    `json:"e_webserveraddr"`
	EWeblogpath    *string    `json:"e_weblogpath"`
	EMemo          *string    `json:"e_memo"`
	EDbtype        *string    `json:"e_dbtype"`
}

type ListResponse struct {
	Total    int       `json:"total"`
	Page     int       `json:"page"`
	PageSize int       `json:"page_size"`
	Data     []EnvInfo `json:"data"`
}

type DataResponse struct {
	Data EnvInfo `json:"data"`
}

type ErrorResponse struct {
	Error  string `json:"error"`
	Detail string `json:"detail,omitempty"`
}

type MessageResponse struct {
	Message string `json:"message"`
}

type RuntimeEnvFreshInfo struct {
	SystemVersion *string    `json:"system_version"`
	SubsystemVer  *string    `json:"subsystem_ver"`
	BeginTime     *time.Time `json:"begin_time"`
}

type RuntimeEnvDiff struct {
	VersionChanged    bool `json:"version_changed"`
	UpdateTimeChanged bool `json:"update_time_changed"`
}

type RuntimeEnvCollectionResult struct {
	ENo         int64                `json:"e_no"`
	EName       *string              `json:"e_name"`
	Status      string               `json:"status"`
	DbType      string               `json:"db_type,omitempty"`
	Current     EnvInfo              `json:"current"`
	Fresh       *RuntimeEnvFreshInfo `json:"fresh,omitempty"`
	Diff        RuntimeEnvDiff       `json:"diff"`
	Error       string               `json:"error,omitempty"`
	CollectedAt time.Time            `json:"collected_at"`
}

type RuntimeCollectPreviewResponse struct {
	Data []RuntimeEnvCollectionResult `json:"data"`
}

type RuntimePublishItem struct {
	ENo           int64      `json:"e_no"`
	SystemVersion *string    `json:"system_version"`
	BeginTime     *time.Time `json:"begin_time"`
	BeginTimeText *string    `json:"begin_time_text"`
}

type RuntimePublishRequest struct {
	Items []RuntimePublishItem `json:"items"`
}

type RuntimePublishResponse struct {
	Updated int       `json:"updated"`
	Skipped []int64   `json:"skipped"`
	Data    []EnvInfo `json:"data"`
}

type DBTypeInfo struct {
	Type                       string `json:"type"`
	Label                      string `json:"label"`
	RuntimeCollectionSupported bool   `json:"runtime_collection_supported"`
}

type DBTypesResponse struct {
	Data []DBTypeInfo `json:"data"`
}

type HealthResponse struct {
	Status      string `json:"status"`
	DbConnected bool   `json:"db_connected"`
}

type VersionResponse struct {
	Version   string `json:"version"`
	Commit    string `json:"commit"`
	BuildTime string `json:"buildTime"`
	GoVersion string `json:"goVersion"`
	Platform  string `json:"platform"`
}
