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
