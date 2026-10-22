package main

import (
	"os"
	"strings"
	"testing"
)

func TestStripScheme(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"https://portainer.example.com", "portainer.example.com"},
		{"http://192.168.1.100:9000", "192.168.1.100:9000"},
		{"portainer.example.com:9443", "portainer.example.com:9443"},
		{"https://localhost", "localhost"},
	}

	for _, tt := range tests {
		result := stripScheme(tt.input)
		if result != tt.expected {
			t.Errorf("stripScheme(%q) = %q, expected %q", tt.input, result, tt.expected)
		}
	}
}

func TestNormalizePortainerURL(t *testing.T) {
	tests := []struct {
		url      string
		useHTTP  bool
		expected string
	}{
		{"https://portainer.example.com", false, "https://portainer.example.com"},
		{"http://portainer.example.com", false, "http://portainer.example.com"},
		{"portainer.example.com", false, "https://portainer.example.com"},
		{"192.168.1.100:9000", true, "http://192.168.1.100:9000"},
		{"192.168.1.100:9443", false, "https://192.168.1.100:9443"},
	}

	for _, tt := range tests {
		result := normalizePortainerURL(tt.url, tt.useHTTP)
		if result != tt.expected {
			t.Errorf("normalizePortainerURL(%q, %v) = %q, expected %q", tt.url, tt.useHTTP, result, tt.expected)
		}
	}
}

func TestBuildMCPCmd_Gen1(t *testing.T) {
	// Pre-seed cache to simulate a Gen 1 binary (v0.x)
	mcpPath := "/usr/local/bin/fake-mcp-v0"
	genCache.Store(mcpPath, MCPGenV0)

	server := "https://my-portainer.com:9443"
	token := "ptr_test_token_123"

	cmd := buildMCPCmd(mcpPath, server, token, true, true, false)

	// Check arguments
	expectedArgs := []string{
		"-server", "my-portainer.com:9443",
		"-token", token,
		"-read-only",
		"-disable-version-check",
	}

	if len(cmd.Args) != len(expectedArgs)+1 { // +1 for binary itself
		t.Fatalf("expected %d args, got %d: %v", len(expectedArgs)+1, len(cmd.Args), cmd.Args)
	}

	for i, arg := range expectedArgs {
		if cmd.Args[i+1] != arg {
			t.Errorf("arg[%d] = %q, expected %q", i+1, cmd.Args[i+1], arg)
		}
	}
}

func TestBuildMCPCmd_Gen2(t *testing.T) {
	// Pre-seed cache to simulate a Gen 2 binary (2.x FastMCP)
	mcpPath := "/usr/local/bin/fake-mcp-v2"
	genCache.Store(mcpPath, MCPGenV2)

	server := "my-portainer.com:9443"
	token := "ptr_test_token_456"

	cmd := buildMCPCmd(mcpPath, server, token, true, true, false)

	// Args should only contain the binary itself (no CLI flags)
	if len(cmd.Args) != 1 {
		t.Fatalf("expected 1 arg (binary only), got %d: %v", len(cmd.Args), cmd.Args)
	}

	// Verify required environment variables are set in cmd.Env
	envMap := make(map[string]string)
	for _, envStr := range cmd.Env {
		parts := strings.SplitN(envStr, "=", 2)
		if len(parts) == 2 {
			envMap[parts[0]] = parts[1]
		}
	}

	if envMap["PORTAINER_URL"] != "https://my-portainer.com:9443" {
		t.Errorf("PORTAINER_URL = %q, expected %q", envMap["PORTAINER_URL"], "https://my-portainer.com:9443")
	}
	if envMap["PORTAINER_API_KEY"] != token {
		t.Errorf("PORTAINER_API_KEY = %q, expected %q", envMap["PORTAINER_API_KEY"], token)
	}
	if envMap["PORTAINER_MCP_TRANSPORT"] != "stdio" {
		t.Errorf("PORTAINER_MCP_TRANSPORT = %q, expected %q", envMap["PORTAINER_MCP_TRANSPORT"], "stdio")
	}
	if envMap["PORTAINER_READ_ONLY"] != "1" {
		t.Errorf("PORTAINER_READ_ONLY = %q, expected %q", envMap["PORTAINER_READ_ONLY"], "1")
	}
	if envMap["PORTAINER_TLS_VERIFY"] != "0" {
		t.Errorf("PORTAINER_TLS_VERIFY = %q, expected %q", envMap["PORTAINER_TLS_VERIFY"], "0")
	}
}

func TestDetectMCPGeneration(t *testing.T) {
	// Create temporary directory for mock scripts
	tmpDir := t.TempDir()

	// Mock Gen 1 script
	gen1Script := tmpDir + "/mock-gen1.sh"
	if err := os.WriteFile(gen1Script, []byte("#!/bin/sh\necho 'Usage of ./portainer-mcp:\n  -server string\n  -token string'\nexit 2\n"), 0755); err != nil {
		t.Fatalf("failed to write mock gen1 script: %v", err)
	}

	// Mock Gen 2 script
	gen2Script := tmpDir + "/mock-gen2.sh"
	if err := os.WriteFile(gen2Script, []byte("#!/bin/sh\necho \"KeyError: 'PORTAINER_URL'\" >&2\nexit 1\n"), 0755); err != nil {
		t.Fatalf("failed to write mock gen2 script: %v", err)
	}

	if gen := DetectMCPGeneration(gen1Script); gen != MCPGenV0 {
		t.Errorf("DetectMCPGeneration(gen1Script) = %v, expected %v", gen, MCPGenV0)
	}

	if gen := DetectMCPGeneration(gen2Script); gen != MCPGenV2 {
		t.Errorf("DetectMCPGeneration(gen2Script) = %v, expected %v", gen, MCPGenV2)
	}
}
