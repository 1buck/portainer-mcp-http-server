package main

import (
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/mdp/qrterminal/v3"
	"github.com/rs/zerolog"
)

//go:embed bundled/*
var bundledBinaries embed.FS

var (
	portainerURL     = flag.String("portainer-url", getEnv("PORTAINER_URL", ""), "Portainer server URL (hostname, IP:port, or full URL)")
	portainerToken   = flag.String("portainer-token", getEnv("PORTAINER_TOKEN", ""), "Portainer API token")
	portainerMCPPath = flag.String("mcp-path", getEnv("MCP_PATH", "portainer-mcp"), "Path to portainer-mcp binary")
	listenAddr       = flag.String("listen", getEnv("MCP_LISTEN", ":8080"), "Listen address")
	baseURL          = flag.String("base-url", getEnv("MCP_BASE_URL", ""), "Base URL for SSE endpoint and QR code")
	readOnly         = flag.Bool("read-only", getEnvBool("MCP_READ_ONLY", false), "Enable read-only mode")
	skipVersionCheck = flag.Bool("skip-version-check", getEnvBool("MCP_SKIP_VERSION_CHECK", false), "Skip Portainer version check")
	debug            = flag.Bool("debug", getEnvBool("MCP_DEBUG", false), "Enable debug logging")
	password         = flag.String("password", getEnv("MCP_PASSWORD", ""), "Password for HTTP Basic Auth (required)")
	useHTTP          = flag.Bool("use-http", getEnvBool("MCP_USE_HTTP", false), "Use HTTP instead of HTTPS for Portainer connection")
)

// getBundledBinaryPath returns the bundled portainer-mcp binary for the current platform.
func getBundledBinaryPath() (string, error) {
	goos := runtime.GOOS
	arch := runtime.GOARCH

	var binaryName string
	if goos == "windows" {
		binaryName = "portainer-mcp-windows-amd64.exe"
	} else if goos == "darwin" {
		if arch == "arm64" {
			binaryName = "portainer-mcp-darwin-arm64"
		} else {
			binaryName = "portainer-mcp-darwin-amd64"
		}
	} else if goos == "linux" {
		if arch == "arm64" {
			binaryName = "portainer-mcp-linux-arm64"
		} else {
			binaryName = "portainer-mcp-linux-amd64"
		}
	} else {
		return "", fmt.Errorf("unsupported OS: %s", goos)
	}

	binaryPath := filepath.Join("bundled", binaryName)
	if _, err := bundledBinaries.Open(binaryPath); err != nil {
		return "", fmt.Errorf("bundled binary %s not found: %w", binaryName, err)
	}

	tmpDir, err := os.MkdirTemp("", "portainer-mcp-*")
	if err != nil {
		return "", fmt.Errorf("failed to create temp dir: %w", err)
	}

	tmpPath := filepath.Join(tmpDir, binaryName)
	data, err := bundledBinaries.ReadFile(binaryPath)
	if err != nil {
		return "", fmt.Errorf("failed to read bundled binary: %w", err)
	}

	if err := os.WriteFile(tmpPath, data, 0755); err != nil {
		return "", fmt.Errorf("failed to write binary: %w", err)
	}

	return tmpPath, nil
}

// findPortainerMCP returns the path to portainer-mcp binary:
func findPortainerMCP(explicitPath string) string {
	if explicitPath != "" && explicitPath != "portainer-mcp" {
		return explicitPath
	}

	if bundledPath, err := getBundledBinaryPath(); err == nil {
		log.Printf("Using bundled portainer-mcp binary: %s", bundledPath)
		return bundledPath
	}

	log.Printf("No bundled binary for this platform, searching PATH for 'portainer-mcp'")

	path, err := exec.LookPath("portainer-mcp")
	if err != nil {
		log.Printf("Warning: portainer-mcp not found in PATH")
		log.Printf("Download from https://github.com/portainer/portainer-mcp/releases")
		return "portainer-mcp"
	}

	return path
}

// getEnv reads an environment variable and returns the value or a default
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvBool reads an environment variable and returns true if it's "true", "1", or "yes"
func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		return value == "true" || value == "1" || value == "yes"
	}
	return defaultValue
}

type MCPSession struct {
	ID        string
	cmd       *exec.Cmd
	stdin     io.WriteCloser
	stdout    io.Reader
	stderr    io.Reader
	eventChan chan json.RawMessage
	done      chan struct{}
	closeOnce sync.Once
}

// normalizePortainerURL handles various URL formats:
// - hostname only: "portainer.example.com" -> "https://portainer.example.com"
// - IP:port: "192.168.1.1:9443" -> "https://192.168.1.1:9443"
// - Full URL: "https://portainer.example.com" -> unchanged
// - With --use-http flag: uses HTTP instead of HTTPS
func normalizePortainerURL(url string, useHTTP bool) string {
	// Already has scheme
	if strings.HasPrefix(url, "http://") || strings.HasPrefix(url, "https://") {
		return url
	}

	// Determine scheme based on --use-http flag
	scheme := "https://"
	if useHTTP {
		scheme = "http://"
	}

	// Add scheme
	return scheme + url
}

// generateQRCode prints an ASCII QR code containing server connection info
func generateQRCode(serverUrl, password string) {
	// Create JSON data for QR
	data := map[string]string{
		"serverUrl": serverUrl,
		"password":  password,
	}
	jsonData, err := json.Marshal(data)
	if err != nil {
		log.Printf("Failed to create QR data: %v", err)
		return
	}

	// Print header
	fmt.Println("\n=== MCP Server QR Code ===")
	fmt.Println("Scan this with Kontainer app to connect:")
	fmt.Println()

	// Generate QR with config
	config := qrterminal.Config{
		Level:      qrterminal.M,
		Writer:     os.Stdout,
		HalfBlocks: true,
	}
	qrterminal.GenerateWithConfig(string(jsonData), config)

	// Print footer
	fmt.Println("\n==========================")
}

func main() {
	flag.Parse()

	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	logger := zerolog.New(os.Stderr).With().Timestamp().Logger()

	if *debug {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	} else {
		zerolog.SetGlobalLevel(zerolog.InfoLevel)
	}

	if *portainerURL == "" {
		logger.Fatal().Msg("--portainer-url is required")
	}

	// Normalize portainer URL - support hostname, IP:port, or full URL
	*portainerURL = normalizePortainerURL(*portainerURL, *useHTTP)
	logger.Info().Str("url", *portainerURL).Msg("Portainer URL configured")

	if *portainerToken == "" {
		logger.Fatal().Msg("--portainer-token is required")
	}
	if *password == "" {
		logger.Fatal().Msg("--password is required")
	}

	// Resolve portainer-mcp binary path (bundled, explicit, or PATH)
	*portainerMCPPath = findPortainerMCP(*portainerMCPPath)

	authMiddleware := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			_, pass, ok := r.BasicAuth()
			if !ok || pass != *password {
				w.Header().Set("WWW-Authenticate", "Basic realm=\"MCP Server\"")
				http.Error(w, "Unauthorized", http.StatusUnauthorized)
				return
			}
			next(w, r)
		}
	}

	sessions := make(map[string]*MCPSession)
	var sessionsMu sync.RWMutex

	http.HandleFunc("/sse", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
			return
		}

		sessionID := uuid.New().String()
		session, err := NewMCPSession(*portainerMCPPath, *portainerURL, *portainerToken, *readOnly, *skipVersionCheck)
		if err != nil {
			logger.Error().Err(err).Msg("Failed to create MCP session")
			http.Error(w, "Failed to create session", http.StatusInternalServerError)
			return
		}

		sessionsMu.Lock()
		sessions[sessionID] = session
		sessionsMu.Unlock()

		defer func() {
			sessionsMu.Lock()
			delete(sessions, sessionID)
			sessionsMu.Unlock()
			session.Close()
		}()

		baseEndpoint := *baseURL
		if baseEndpoint == "" {
			baseEndpoint = fmt.Sprintf("http://%s", r.Host)
		}
		messageEndpoint := fmt.Sprintf("%s/mcp/message?sessionId=%s", baseEndpoint, sessionID)

		fmt.Fprintf(w, "event: endpoint\ndata: %s\n\n", messageEndpoint)
		flusher.Flush()

		logger.Info().Str("session", sessionID).Msg("SSE connection established")

		for {
			select {
			case msg := <-session.eventChan:
				fmt.Fprintf(w, "event: message\ndata: %s\n\n", msg)
				flusher.Flush()
			case <-session.done:
				return
			case <-r.Context().Done():
				return
			}
		}
	}))

	http.HandleFunc("/mcp/message", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		sessionID := r.URL.Query().Get("sessionId")
		if sessionID == "" {
			http.Error(w, "Missing sessionId", http.StatusBadRequest)
			return
		}

		sessionsMu.RLock()
		session, ok := sessions[sessionID]
		sessionsMu.RUnlock()

		if !ok {
			http.Error(w, "Invalid session", http.StatusBadRequest)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", http.StatusBadRequest)
			return
		}

		if err := session.SendMessage(body); err != nil {
			logger.Error().Err(err).Msg("Failed to send message to MCP")
			http.Error(w, "Failed to send message", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusAccepted)
	}))

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "OK")
	})

	http.HandleFunc("/connect", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		logger.Debug().Str("portainerURL", *portainerURL).Msg("Testing Portainer connection")

		client := &http.Client{Timeout: 10 * time.Second}

		statusURL := fmt.Sprintf("%s/api/status", *portainerURL)
		logger.Debug().Str("statusURL", statusURL).Msg("Fetching Portainer status")

		req, err := http.NewRequest("GET", statusURL, nil)
		if err != nil {
			logger.Error().Err(err).Msg("Failed to create request")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("Failed to create request: %v", err),
			})
			return
		}
		req.Header.Set("X-API-Key", *portainerToken)

		resp, err := client.Do(req)
		if err != nil {
			logger.Error().Err(err).Msg("Failed to connect to Portainer")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("Failed to connect to Portainer: %v", err),
			})
			return
		}
		defer resp.Body.Close()

		logger.Debug().Int("statusCode", resp.StatusCode).Msg("Portainer response")

		if resp.StatusCode == http.StatusUnauthorized {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"error":   "Invalid Portainer API token",
			})
			return
		}

		if resp.StatusCode >= 400 {
			body, _ := io.ReadAll(resp.Body)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("Portainer returned status %d: %s", resp.StatusCode, string(body)),
			})
			return
		}

		var statusData map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&statusData); err != nil {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("Failed to parse Portainer response: %v", err),
			})
			return
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Connection successful",
			"version": statusData["Version"],
		})
	}))

	serverReady := make(chan struct{})
	serverErr := make(chan error, 1)

	go func() {
		logger.Info().Str("address", *listenAddr).Msg("Starting Portainer MCP HTTP server")
		close(serverReady) // Signal server starting
		if err := http.ListenAndServe(*listenAddr, nil); err != nil && err != http.ErrServerClosed {
			serverErr <- err
		}
	}()

	<-serverReady // Wait for server

	baseEndpoint := *baseURL
	if baseEndpoint == "" {
		baseEndpoint = fmt.Sprintf("http://%s", *listenAddr)
		if strings.HasPrefix(*listenAddr, ":") {
			// For ":8080" format, construct full URL
			hostname, _ := os.Hostname()
			if hostname == "" {
				hostname = "localhost"
			}
			baseEndpoint = fmt.Sprintf("http://%s%s", hostname, *listenAddr)
		}
	}
	generateQRCode(baseEndpoint, *password)

	// Check for server startup errors
	select {
	case err := <-serverErr:
		logger.Fatal().Err(err).Msg("Server failed to start")
	default:
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info().Msg("Shutting down server...")
	sessionsMu.Lock()
	for _, session := range sessions {
		session.Close()
	}
	sessionsMu.Unlock()
	logger.Info().Msg("Server stopped")
}

func NewMCPSession(mcpPath, url, token string, readOnly, skipVersionCheck bool) (*MCPSession, error) {
	args := []string{
		"-server", url,
		"-token", token,
	}
	if readOnly {
		args = append(args, "-read-only")
	}
	if skipVersionCheck {
		args = append(args, "-disable-version-check")
	}

	cmd := exec.Command(mcpPath, args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to create stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to create stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to create stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("failed to start portainer-mcp: %w", err)
	}

	session := &MCPSession{
		ID:        uuid.New().String(),
		cmd:       cmd,
		stdin:     stdin,
		stdout:    stdout,
		stderr:    stderr,
		eventChan: make(chan json.RawMessage, 100),
		done:      make(chan struct{}),
	}

	go session.readLoop()
	go session.stderrLoop()

	return session, nil
}

func (s *MCPSession) SendMessage(msg json.RawMessage) error {
	_, err := s.stdin.Write(append(msg, '\n'))
	return err
}

func (s *MCPSession) readLoop() {
	decoder := json.NewDecoder(s.stdout)
	for {
		select {
		case <-s.done:
			return
		default:
			var msg json.RawMessage
			if err := decoder.Decode(&msg); err != nil {
				if err != io.EOF {
					log.Printf("Read error: %v", err)
				}
				s.Close()
				return
			}

			log.Printf("Received from MCP: %s", string(msg))

			select {
			case s.eventChan <- msg:
				log.Printf("Sent to eventChan")
			default:
				log.Printf("eventChan full, dropping message")
			}
		}
	}
}

func (s *MCPSession) stderrLoop() {
	buf := make([]byte, 1024)
	for {
		n, err := s.stderr.Read(buf)
		if err != nil {
			return
		}
		log.Printf("[portainer-mcp stderr] %s", string(buf[:n]))
	}
}

func (s *MCPSession) Close() {
	s.closeOnce.Do(func() {
		close(s.done)
		s.stdin.Close()
		if s.cmd.Process != nil {
			s.cmd.Process.Kill()
			s.cmd.Wait()
		}
	})
}
