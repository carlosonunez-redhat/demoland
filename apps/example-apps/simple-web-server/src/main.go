package main

import (
	"embed"
	"fmt"
	"net/http"
	"os"
	"strings"

	log "github.com/sirupsen/logrus"
)

//go:embed templates/page.html
var templateFS embed.FS

var (
	Version   = "dev"
	CommitSHA = "unknown"
	BuildDate = "unknown"
	ToolName  = "simple-load-tester-web-server"
)

func main() {
	configureLogging()

	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Println(versionString())
		os.Exit(0)
	}

	mux := http.NewServeMux()
	mux.Handle("/", timingMiddleware(requestHandler()))

	addr := serverAddr()
	log.Infof("Starting server on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.WithError(err).Error("Server failed to start")
		os.Exit(1)
	}
}

func versionString() string {
	return fmt.Sprintf("%s version %s (Commit: %s, Last Updated: %s)",
		ToolName, Version, CommitSHA, BuildDate)
}

func serverAddr() string {
	if port := os.Getenv("PORT"); port != "" {
		return ":" + port
	}
	return ":8000"
}

func configureLogging() {
	log.SetFormatter(&log.TextFormatter{FullTimestamp: true})

	levelStr := strings.ToLower(os.Getenv("LOG_LEVEL"))
	switch levelStr {
	case "trace":
		log.SetLevel(log.TraceLevel)
	case "debug":
		log.SetLevel(log.DebugLevel)
	case "warn", "warning":
		log.SetLevel(log.WarnLevel)
	case "error":
		log.SetLevel(log.ErrorLevel)
	default:
		log.SetLevel(log.InfoLevel)
	}
}
