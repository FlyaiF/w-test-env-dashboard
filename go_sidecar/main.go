package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"test-env-dashboard/go_sidecar/db"
	"test-env-dashboard/go_sidecar/handler"
)

func main() {
	dsn := flag.String("dsn", "", "Oracle DSN (oracle://user:pass@host:port/service)")
	testDsn := flag.String("test-dsn", "", "Test a runtime database DSN and exit")
	testDBType := flag.String("test-db-type", db.RuntimeDBOracle, "Runtime database type for --test-dsn")
	listen := flag.String("listen", "127.0.0.1:0", "Listen address (default: random port)")
	flag.Parse()

	if *testDsn != "" {
		if err := db.TestRuntimeConnection(*testDBType, *testDsn); err != nil {
			fmt.Fprintf(os.Stderr, "DB_ERROR=%s\n", err.Error())
			os.Exit(1)
		}
		fmt.Println("connection successful")
		return
	}

	if *dsn == "" {
		fmt.Fprintln(os.Stderr, "error: --dsn is required")
		os.Exit(1)
	}

	// Connect to Oracle
	log.Println("Connecting to Oracle...")
	if err := db.Init(*dsn); err != nil {
		fmt.Fprintf(os.Stderr, "DB_ERROR=%s\n", err.Error())
		os.Stdout.Sync()
		os.Exit(1)
	}
	defer db.Close()
	log.Println("Oracle connected.")

	// Setup routes
	mux := http.NewServeMux()
	mux.HandleFunc("/health", handler.Health)
	mux.HandleFunc("/version", handler.Version)
	mux.HandleFunc("/api/runtime-env/collect-preview", handler.CollectPreview)
	mux.HandleFunc("/api/runtime-env/publish-collected", handler.PublishCollected)
	// Backward-compatible aliases for clients built before the route was moved.
	mux.HandleFunc("/api/envs/collect-preview", handler.CollectPreview)
	mux.HandleFunc("/api/envs/publish-collected", handler.PublishCollected)
	mux.HandleFunc("/api/envs", handler.Envs)
	mux.HandleFunc("/api/envs/", handler.EnvByID)
	mux.HandleFunc("/api/db/test", handler.TestDB)
	mux.HandleFunc("/api/db/types", handler.DBTypes)

	// Listen on specified address
	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	port := ln.Addr().(*net.TCPAddr).Port
	// Print port for Flutter to read — this is the IPC protocol
	fmt.Printf("PORT=%d\n", port)
	os.Stdout.Sync()

	log.Printf("Sidecar listening on 127.0.0.1:%d", port)

	// Graceful shutdown on SIGTERM/SIGINT
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
		<-sig
		log.Println("Shutting down...")
		ln.Close()
	}()

	if err := http.Serve(ln, handler.Chain(mux)); err != nil {
		// Closed listener is expected on shutdown
		if opErr, ok := err.(*net.OpError); ok && opErr.Op == "accept" {
			os.Exit(0)
		}
		log.Fatalf("serve: %v", err)
	}
}
