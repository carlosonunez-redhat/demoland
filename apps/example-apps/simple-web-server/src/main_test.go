package main

import (
	"fmt"
	"testing"

	log "github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
)

type ConfigureLoggingTest struct {
	Name      string
	EnvValue  string
	WantLevel log.Level
}

func (tc *ConfigureLoggingTest) Run(t *testing.T) {
	t.Helper()
	t.Setenv("LOG_LEVEL", tc.EnvValue)
	configureLogging()
	assert.Equal(t, tc.WantLevel, log.GetLevel(), "[%s] unexpected log level", tc.Name)
}

func TestConfigureLogging(t *testing.T) {
	tests := []ConfigureLoggingTest{
		{Name: "default_is_info", EnvValue: "", WantLevel: log.InfoLevel},
		{Name: "info", EnvValue: "info", WantLevel: log.InfoLevel},
		{Name: "warn", EnvValue: "warn", WantLevel: log.WarnLevel},
		{Name: "warning", EnvValue: "warning", WantLevel: log.WarnLevel},
		{Name: "error", EnvValue: "error", WantLevel: log.ErrorLevel},
		{Name: "debug", EnvValue: "debug", WantLevel: log.DebugLevel},
		{Name: "trace", EnvValue: "trace", WantLevel: log.TraceLevel},
		{Name: "case_insensitive", EnvValue: "DEBUG", WantLevel: log.DebugLevel},
	}
	for _, tc := range tests {
		t.Run(tc.Name, func(t *testing.T) {
			tc.Run(t)
		})
	}
}

type ServerAddrTest struct {
	Name     string
	EnvValue string
	Want     string
}

func (tc *ServerAddrTest) Run(t *testing.T) {
	t.Helper()
	t.Setenv("PORT", tc.EnvValue)
	got := serverAddr()
	assert.Equal(t, tc.Want, got, "[%s] unexpected addr", tc.Name)
}

func TestServerAddr(t *testing.T) {
	tests := []ServerAddrTest{
		{Name: "default_is_8000", EnvValue: "", Want: ":8000"},
		{Name: "custom_port", EnvValue: "9090", Want: ":9090"},
		{Name: "another_port", EnvValue: "3000", Want: ":3000"},
	}
	for _, tc := range tests {
		t.Run(tc.Name, func(t *testing.T) {
			tc.Run(t)
		})
	}
}

func TestVersionString(t *testing.T) {
	Version = "1.2.3"
	CommitSHA = "abc1234"
	BuildDate = "2026-01-01"

	want := fmt.Sprintf("%s version %s (Commit: %s, Last Updated: %s)", ToolName, Version, CommitSHA, BuildDate)
	got := versionString()
	assert.Equal(t, want, got)
}
