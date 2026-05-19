package db

import (
	"errors"
	"test-env-dashboard/go_sidecar/model"
	"testing"
	"time"
)

func TestBuildRuntimeCollectionResultChanged(t *testing.T) {
	currentVersion := "1.0.0"
	freshVersion := "1.0.1"
	currentTime := time.Date(2026, 4, 25, 9, 0, 0, 0, time.UTC)
	freshTime := currentTime.Add(time.Minute)

	result := BuildRuntimeCollectionResult(
		model.EnvInfo{
			ENo:         10,
			EVersion:    &currentVersion,
			EUpdatetime: &currentTime,
		},
		model.RuntimeEnvFreshInfo{
			SystemVersion: &freshVersion,
			BeginTime:     &freshTime,
		},
		time.Now(),
	)

	if result.Status != "changed" {
		t.Fatalf("Status = %q, want changed", result.Status)
	}
	if !result.Diff.VersionChanged {
		t.Fatal("VersionChanged = false, want true")
	}
	if !result.Diff.UpdateTimeChanged {
		t.Fatal("UpdateTimeChanged = false, want true")
	}
}

func TestBuildRuntimeCollectionResultUnchangedNormalizesValues(t *testing.T) {
	currentVersion := " 1.0.0 "
	freshVersion := "1.0.0"
	currentTime := time.Date(2026, 4, 25, 9, 0, 0, 500, time.UTC)
	freshTime := currentTime.In(time.FixedZone("CST", 8*60*60)).Add(400 * time.Nanosecond)

	result := BuildRuntimeCollectionResult(
		model.EnvInfo{
			ENo:         10,
			EVersion:    &currentVersion,
			EUpdatetime: &currentTime,
		},
		model.RuntimeEnvFreshInfo{
			SystemVersion: &freshVersion,
			BeginTime:     &freshTime,
		},
		time.Now(),
	)

	if result.Status != "unchanged" {
		t.Fatalf("Status = %q, want unchanged", result.Status)
	}
	if result.Diff.VersionChanged {
		t.Fatal("VersionChanged = true, want false")
	}
	if result.Diff.UpdateTimeChanged {
		t.Fatal("UpdateTimeChanged = true, want false")
	}
}

func TestBuildRuntimeSkippedAndFailedResults(t *testing.T) {
	env := model.EnvInfo{ENo: 7}
	skipped := BuildRuntimeSkippedResult(env, "E_YWDB is empty", time.Now())
	if skipped.Status != "skipped" || skipped.Error == "" {
		t.Fatalf("skipped result = %#v", skipped)
	}

	failed := BuildRuntimeFailedResult(env, errors.New("boom"), time.Now())
	if failed.Status != "failed" || failed.Error != "boom" {
		t.Fatalf("failed result = %#v", failed)
	}

	unsupported := BuildRuntimeUnsupportedResult(env, "not supported", time.Now())
	if unsupported.Status != "unsupported" || unsupported.Error != "not supported" {
		t.Fatalf("unsupported result = %#v", unsupported)
	}
}

func TestNormalizeOracleDSN(t *testing.T) {
	dashboardDSN = "oracle://dash:secret@meta-host:1521/meta"

	tests := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "already oracle url",
			raw:  "oracle://u:p@host:1521/service",
			want: "oracle://u:p@host:1521/service",
		},
		{
			name: "jdbc no credentials",
			raw:  "jdbc:oracle:thin:@//10.0.0.1:1521/orcl",
			want: "oracle://dash:secret@10.0.0.1:1521/orcl",
		},
		{
			name: "jdbc with credentials",
			raw:  "jdbc:oracle:thin:app/pass@10.0.0.2:1521:orcl",
			want: "oracle://app:pass@10.0.0.2:1521/orcl",
		},
		{
			name: "plain address",
			raw:  "10.0.0.3:1521/service",
			want: "oracle://dash:secret@10.0.0.3:1521/service",
		},
		{
			name: "plain address default port",
			raw:  "10.0.0.3/service",
			want: "oracle://dash:secret@10.0.0.3:1521/service",
		},
		{
			name: "plain credentials",
			raw:  "app/pass@10.0.0.4:1521/service",
			want: "oracle://app:pass@10.0.0.4:1521/service",
		},
		{
			name: "plain credentials default port",
			raw:  "app/pass@10.0.0.4/service",
			want: "oracle://app:pass@10.0.0.4:1521/service",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := normalizeOracleDSN(tt.raw)
			if err != nil {
				t.Fatalf("normalizeOracleDSN() error = %v", err)
			}
			if got != tt.want {
				t.Fatalf("normalizeOracleDSN() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestNormalizeDamengDSN(t *testing.T) {
	fallback := RuntimeDBCredentials{Username: "dash", Password: "secret"}
	adapter := damengRuntimeAdapter{}

	tests := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "already dm url",
			raw:  "dm://u:p@host:5236?schema=APP",
			want: "dm://u:p@host:5236?schema=APP",
		},
		{
			name: "jdbc dm url",
			raw:  "jdbc:dm://u:p@host:5236?schema=APP",
			want: "dm://u:p@host:5236?schema=APP",
		},
		{
			name: "plain credentials",
			raw:  "app/pass@10.0.0.4:5236",
			want: "dm://app:pass@10.0.0.4:5236",
		},
		{
			name: "plain credentials default port",
			raw:  "app/pass@10.0.0.4",
			want: "dm://app:pass@10.0.0.4:5236",
		},
		{
			name: "plain address with fallback credentials",
			raw:  "10.0.0.5:5236?schema=APP",
			want: "dm://dash:secret@10.0.0.5:5236?schema=APP",
		},
		{
			name: "plain address default port with fallback credentials",
			raw:  "10.0.0.5",
			want: "dm://dash:secret@10.0.0.5:5236",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := adapter.normalizeDSN(tt.raw, fallback)
			if err != nil {
				t.Fatalf("normalizeDSN() error = %v", err)
			}
			if got != tt.want {
				t.Fatalf("normalizeDSN() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestNormalizeOceanBaseOracleDSN(t *testing.T) {
	fallback := RuntimeDBCredentials{Username: "dash@oracle_tenant", Password: "secret"}
	adapter := oceanBaseOracleRuntimeAdapter{}

	tests := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "already jdbc url",
			raw:  "jdbc:oceanbase:oracle://10.0.0.1:2881/ob?user=u&password=p",
			want: "jdbc:oceanbase:oracle://10.0.0.1:2881/ob?user=u&password=p",
		},
		{
			name: "plain credentials",
			raw:  "obfz@oracle_tenant/handsome@10.20.161.98:2881/obfz",
			want: "jdbc:oceanbase:oracle://10.20.161.98:2881/obfz?connectTimeout=5000&socketTimeout=15000&user=obfz@oracle_tenant&password=handsome",
		},
		{
			name: "plain credentials default port",
			raw:  "obfz@oracle_tenant/handsome@10.20.161.98/obfz",
			want: "jdbc:oceanbase:oracle://10.20.161.98:2881/obfz?connectTimeout=5000&socketTimeout=15000&user=obfz@oracle_tenant&password=handsome",
		},
		{
			name: "plain address with fallback credentials",
			raw:  "10.20.161.98:2881/obfz",
			want: "jdbc:oceanbase:oracle://10.20.161.98:2881/obfz?connectTimeout=5000&socketTimeout=15000&user=dash@oracle_tenant&password=secret",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := adapter.normalizeDSN(tt.raw, fallback)
			if err != nil {
				t.Fatalf("normalizeDSN() error = %v", err)
			}
			if got != tt.want {
				t.Fatalf("normalizeDSN() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestNormalizeRuntimeDBType(t *testing.T) {
	tests := map[string]string{
		"":                 RuntimeDBOracle,
		"0":                RuntimeDBOracle,
		"oracle":           RuntimeDBOracle,
		"1":                RuntimeDBOceanBaseOracle,
		"2":                RuntimeDBDameng,
		"dm":               RuntimeDBDameng,
		"Dameng":           RuntimeDBDameng,
		"oceanbase":        RuntimeDBOceanBaseOracle,
		"oceanbase_oracle": RuntimeDBOceanBaseOracle,
		"OceanBase Oracle": RuntimeDBOceanBaseOracle,
		"custom-db":        "custom-db",
	}

	for input, want := range tests {
		if got := NormalizeRuntimeDBType(input); got != want {
			t.Fatalf("NormalizeRuntimeDBType(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestParseJDBCTime(t *testing.T) {
	got, err := parseJDBCTime("2026-05-18 09:55:01.0")
	if err != nil {
		t.Fatalf("parseJDBCTime() error = %v", err)
	}
	if got.Year() != 2026 || got.Month() != 5 || got.Day() != 18 ||
		got.Hour() != 9 || got.Minute() != 55 || got.Second() != 1 {
		t.Fatalf("parseJDBCTime() = %s", got)
	}
}

func TestBuildPublishCollectedSQLUsesOracleDateConversion(t *testing.T) {
	version := "TA6.0"
	beginTimeText := "2026-04-25 13:14:15"

	q, args := buildPublishCollectedSQL(model.RuntimePublishItem{
		ENo:           42,
		SystemVersion: &version,
		BeginTimeText: &beginTimeText,
	})

	wantSQL := "UPDATE TENVINFO SET E_VERSION = :1, E_UPDATETIME = TO_DATE(:2, 'YYYY-MM-DD HH24:MI:SS') WHERE E_NO = :3"
	if q != wantSQL {
		t.Fatalf("sql = %q, want %q", q, wantSQL)
	}
	if len(args) != 3 {
		t.Fatalf("len(args) = %d, want 3", len(args))
	}
	if args[0] != version {
		t.Fatalf("version arg = %#v", args[0])
	}
	if args[1] != "2026-04-25 13:14:15" {
		t.Fatalf("time arg = %#v", args[1])
	}
	if args[2] != int64(42) {
		t.Fatalf("id arg = %#v", args[2])
	}
}
