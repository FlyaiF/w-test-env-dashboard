package db

import (
	"database/sql"
	"fmt"
	"net/url"
	"time"

	_ "github.com/sijms/go-ora/v2"
)

var pool *sql.DB
var dashboardDSN string

func Init(dsn string) error {
	var err error
	dashboardDSN = dsn
	pool, err = sql.Open("oracle", dsn)
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}
	pool.SetMaxOpenConns(5)
	pool.SetMaxIdleConns(2)
	pool.SetConnMaxLifetime(30 * time.Minute)
	return pool.Ping()
}

func Pool() *sql.DB {
	return pool
}

func Close() {
	if pool != nil {
		pool.Close()
	}
}

func TestConnection(dsn string) error {
	db, err := sql.Open("oracle", dsn)
	if err != nil {
		return err
	}
	defer db.Close()
	db.SetConnMaxLifetime(10 * time.Second)
	return db.Ping()
}

func dashboardCredentials() (string, string, bool) {
	u, err := url.Parse(dashboardDSN)
	if err != nil || u.User == nil {
		return "", "", false
	}
	username := u.User.Username()
	password, _ := u.User.Password()
	return username, password, username != ""
}
