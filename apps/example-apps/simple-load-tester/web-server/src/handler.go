package main

import (
	"context"
	"fmt"
	"html/template"
	"net/http"
	"time"

	log "github.com/sirupsen/logrus"
)

const maxBodySnippet = 200

type PageData struct {
	Method      string
	Detail      string
	ElapsedSecs string
}

type contextKey string

const ctxKeyStart contextKey = "requestStart"

var mutatingMethods = map[string]bool{
	http.MethodPost:   true,
	http.MethodPut:    true,
	http.MethodPatch:  true,
	http.MethodDelete: true,
}

func requestHandler() http.Handler {
	tmpl := template.Must(template.ParseFS(templateFS, "templates/page.html"))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := r.Context().Value(ctxKeyStart).(time.Time)
		elapsed := time.Since(start)

		var detail string
		if mutatingMethods[r.Method] {
			detail = readBodySnippet(r, maxBodySnippet)
		} else {
			detail = r.URL.Path
		}

		data := PageData{
			Method:      r.Method,
			Detail:      detail,
			ElapsedSecs: fmt.Sprintf("%.6f", elapsed.Seconds()),
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := tmpl.Execute(w, data); err != nil {
			log.Errorf("Failed to render template: %v", err)
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}

		log.WithFields(log.Fields{
			"method":  r.Method,
			"path":    r.URL.Path,
			"elapsed": elapsed.String(),
		}).Info("Request handled")
	})
}

func readBodySnippet(r *http.Request, maxLen int) string {
	if r.Body == nil {
		return "(no body)"
	}
	defer r.Body.Close()

	buf := make([]byte, maxLen+1)
	n, err := r.Body.Read(buf)
	if n == 0 && err != nil {
		return "(empty body)"
	}

	snippet := string(buf[:n])
	if n > maxLen {
		snippet = snippet[:maxLen] + "..."
	}
	return snippet
}

func timingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ctx := context.WithValue(r.Context(), ctxKeyStart, start)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
