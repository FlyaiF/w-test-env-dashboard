package db

import (
	"database/sql"
	"fmt"
	"strings"
	"test-env-dashboard/go_sidecar/model"
	"time"
)

func scanEnv(row interface{ Scan(...any) error }) (model.EnvInfo, error) {
	var e model.EnvInfo
	var updatetime sql.NullTime
	err := row.Scan(
		&e.ENo, &e.EName, &e.EYwdb, &e.EZjdb, &e.EUrl,
		&e.EVersion, &updatetime, &e.ESeeurl, &e.EWebserveraddr,
		&e.EWeblogpath, &e.EMemo, &e.EDbtype,
	)
	if err != nil {
		return e, err
	}
	if updatetime.Valid {
		e.EUpdatetime = &updatetime.Time
	}
	return e, nil
}

const selectColumns = `E_NO, E_NAME, E_YWDB, E_ZJDB, E_URL, E_VERSION,
	E_UPDATETIME, E_SEEURL, E_WEBSERVERADDR, E_WEBLOGPATH, E_MEMO, E_DBTYPE`

func ListEnvs(search string, page, pageSize int) ([]model.EnvInfo, int, error) {
	where := ""
	var args []any
	if search != "" {
		where = ` WHERE LOWER(E_NAME) LIKE :1 OR LOWER(E_URL) LIKE :2 OR LOWER(E_MEMO) LIKE :3 OR LOWER(E_VERSION) LIKE :4`
		pat := "%" + strings.ToLower(search) + "%"
		args = append(args, pat, pat, pat, pat)
	}

	// Count total
	countSQL := "SELECT COUNT(*) FROM TENVINFO" + where
	var total int
	err := pool.QueryRow(countSQL, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count: %w", err)
	}

	// Fetch page
	offset := (page - 1) * pageSize
	dataSQL := fmt.Sprintf(
		"SELECT %s FROM TENVINFO%s ORDER BY E_NO OFFSET :o ROWS FETCH NEXT :n ROWS ONLY",
		selectColumns, where,
	)
	dataArgs := append(args, sql.Named("o", offset), sql.Named("n", pageSize))

	rows, err := pool.Query(dataSQL, dataArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("query: %w", err)
	}
	defer rows.Close()

	var list []model.EnvInfo
	for rows.Next() {
		e, err := scanEnv(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan: %w", err)
		}
		list = append(list, e)
	}
	return list, total, rows.Err()
}

func GetEnv(id int64) (model.EnvInfo, error) {
	q := fmt.Sprintf("SELECT %s FROM TENVINFO WHERE E_NO = :1", selectColumns)
	row := pool.QueryRow(q, id)
	return scanEnv(row)
}

func CreateEnv(e model.EnvInfo) error {
	q := `INSERT INTO TENVINFO (E_NO, E_NAME, E_YWDB, E_ZJDB, E_URL, E_VERSION,
		E_UPDATETIME, E_SEEURL, E_WEBSERVERADDR, E_WEBLOGPATH, E_MEMO, E_DBTYPE)
		VALUES (:1, :2, :3, :4, :5, :6, SYSDATE, :7, :8, :9, :10, :11)`
	_, err := pool.Exec(q,
		e.ENo, e.EName, e.EYwdb, e.EZjdb, e.EUrl, e.EVersion,
		e.ESeeurl, e.EWebserveraddr, e.EWeblogpath, e.EMemo, e.EDbtype,
	)
	return err
}

func UpdateEnv(id int64, e model.EnvInfo) error {
	var setClauses []string
	var args []any
	idx := 1

	addField := func(col string, val any) {
		setClauses = append(setClauses, fmt.Sprintf("%s = :%d", col, idx))
		args = append(args, val)
		idx++
	}

	if e.EName != nil {
		addField("E_NAME", *e.EName)
	}
	if e.EYwdb != nil {
		addField("E_YWDB", *e.EYwdb)
	}
	if e.EZjdb != nil {
		addField("E_ZJDB", *e.EZjdb)
	}
	if e.EUrl != nil {
		addField("E_URL", *e.EUrl)
	}
	if e.EVersion != nil {
		addField("E_VERSION", *e.EVersion)
	}
	if e.ESeeurl != nil {
		addField("E_SEEURL", *e.ESeeurl)
	}
	if e.EWebserveraddr != nil {
		addField("E_WEBSERVERADDR", *e.EWebserveraddr)
	}
	if e.EWeblogpath != nil {
		addField("E_WEBLOGPATH", *e.EWeblogpath)
	}
	if e.EMemo != nil {
		addField("E_MEMO", *e.EMemo)
	}
	if e.EDbtype != nil {
		addField("E_DBTYPE", *e.EDbtype)
	}

	if len(setClauses) == 0 {
		return nil
	}

	// Always update timestamp
	setClauses = append(setClauses, "E_UPDATETIME = SYSDATE")

	q := fmt.Sprintf("UPDATE TENVINFO SET %s WHERE E_NO = :%d",
		strings.Join(setClauses, ", "), idx)
	args = append(args, id)

	result, err := pool.Exec(q, args...)
	if err != nil {
		return err
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func DeleteEnv(id int64) error {
	result, err := pool.Exec("DELETE FROM TENVINFO WHERE E_NO = :1", id)
	if err != nil {
		return err
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func Now() time.Time {
	return time.Now()
}
