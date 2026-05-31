package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type ReadBodySnippetTest struct {
	Name string
	Body io.Reader
	Max  int
	Want string
}

func (tc *ReadBodySnippetTest) Run(t *testing.T) {
	t.Helper()
	var r *http.Request
	if tc.Body != nil {
		r = httptest.NewRequest(http.MethodPost, "/", tc.Body)
	} else {
		r = httptest.NewRequest(http.MethodPost, "/", nil)
		r.Body = nil
	}
	got := readBodySnippet(r, tc.Max)
	assert.Equal(t, tc.Want, got, "[%s] unexpected snippet", tc.Name)
}

func TestReadBodySnippet(t *testing.T) {
	tests := []ReadBodySnippetTest{
		{Name: "nil_body", Body: nil, Max: 200, Want: "(no body)"},
		{Name: "empty_body", Body: strings.NewReader(""), Max: 200, Want: "(empty body)"},
		{Name: "short_body", Body: strings.NewReader("hello"), Max: 200, Want: "hello"},
		{Name: "exact_limit", Body: strings.NewReader(strings.Repeat("a", 200)), Max: 200, Want: strings.Repeat("a", 200)},
		{Name: "over_limit", Body: strings.NewReader(strings.Repeat("x", 300)), Max: 200, Want: strings.Repeat("x", 200) + "..."},
	}
	for _, tc := range tests {
		t.Run(tc.Name, func(t *testing.T) {
			tc.Run(t)
		})
	}
}

type RequestHandlerTest struct {
	Name       string
	Method     string
	Path       string
	Body       string
	WantInH1   string
	WantInH2   string
	WantStatus int
}

func (tc *RequestHandlerTest) Run(t *testing.T) {
	t.Helper()

	var body io.Reader
	if tc.Body != "" {
		body = strings.NewReader(tc.Body)
	}

	req := httptest.NewRequest(tc.Method, tc.Path, body)
	ctx := context.WithValue(req.Context(), ctxKeyStart, time.Now())
	req = req.WithContext(ctx)

	rr := httptest.NewRecorder()
	handler := requestHandler()
	handler.ServeHTTP(rr, req)

	assert.Equal(t, tc.WantStatus, rr.Code, "[%s] unexpected status code", tc.Name)

	respBody := rr.Body.String()
	assert.Contains(t, respBody, "<h1>"+tc.WantInH1+"</h1>", "[%s] h1 mismatch", tc.Name)
	assert.Contains(t, respBody, "<h2>"+tc.WantInH2+"</h2>", "[%s] h2 mismatch", tc.Name)
	assert.Contains(t, respBody, "<h3>", "[%s] missing h3 elapsed time", tc.Name)
	assert.Contains(t, respBody, "s</h3>", "[%s] h3 should end with 's'", tc.Name)
}

func TestRequestHandler(t *testing.T) {
	tests := []RequestHandlerTest{
		{Name: "get_shows_path", Method: http.MethodGet, Path: "/hello/world", WantInH1: "GET", WantInH2: "/hello/world", WantStatus: http.StatusOK},
		{Name: "head_shows_path", Method: http.MethodHead, Path: "/status", WantInH1: "HEAD", WantInH2: "/status", WantStatus: http.StatusOK},
		{Name: "options_shows_path", Method: http.MethodOptions, Path: "/api", WantInH1: "OPTIONS", WantInH2: "/api", WantStatus: http.StatusOK},
		{Name: "post_shows_body", Method: http.MethodPost, Path: "/submit", Body: `{"key":"value"}`, WantInH1: "POST", WantInH2: `{&#34;key&#34;:&#34;value&#34;}`, WantStatus: http.StatusOK},
		{Name: "put_shows_body", Method: http.MethodPut, Path: "/update", Body: "update payload", WantInH1: "PUT", WantInH2: "update payload", WantStatus: http.StatusOK},
		{Name: "patch_shows_body", Method: http.MethodPatch, Path: "/patch", Body: "patch data", WantInH1: "PATCH", WantInH2: "patch data", WantStatus: http.StatusOK},
		{Name: "delete_empty_body", Method: http.MethodDelete, Path: "/remove", Body: "", WantInH1: "DELETE", WantInH2: "(empty body)", WantStatus: http.StatusOK},
		{Name: "post_long_body_truncated", Method: http.MethodPost, Path: "/big", Body: strings.Repeat("x", 300), WantInH1: "POST", WantInH2: strings.Repeat("x", 200) + "...", WantStatus: http.StatusOK},
	}
	for _, tc := range tests {
		t.Run(tc.Name, func(t *testing.T) {
			tc.Run(t)
		})
	}
}

func TestTimingMiddleware(t *testing.T) {
	var capturedStart time.Time
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		val := r.Context().Value(ctxKeyStart)
		require.NotNil(t, val, "context should contain start time")
		capturedStart = val.(time.Time)
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rr := httptest.NewRecorder()

	before := time.Now()
	timingMiddleware(inner).ServeHTTP(rr, req)

	assert.False(t, capturedStart.IsZero(), "start time should be set")
	assert.True(t, !capturedStart.Before(before), "start time should be >= before")
}
