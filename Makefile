.PHONY: build clean docker release run

VERSION := v0.7.0
PORTAINER_MCP_VERSION := v0.7.0
BINARY := portainer-mcp-server
LDFLAGS := -ldflags="-s -w -X main.Version=$(VERSION)"

build:
	go build $(LDFLAGS) -o $(BINARY) .

clean:
	rm -f $(BINARY)
	rm -rf dist/
	rm -rf bundled/

docker:
	docker build -t portainer-mcp-server .

release: clean download-mcp-bundled
	mkdir -p dist
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o dist/$(BINARY)-linux-arm64 .
	GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-darwin-amd64 .
	GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o dist/$(BINARY)-darwin-arm64 .
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-windows-amd64.exe .
	cp bundled/* dist/

download-mcp-bundled:
	mkdir -p bundled
	@echo "Downloading portainer-mcp binaries (some platforms may not be available)..."
	@echo "Linux AMD64..."
	curl -sL -o bundled/portainer-mcp-linux-amd64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-linux-amd64.tar.gz && \
		tar -xzf bundled/portainer-mcp-linux-amd64.tar.gz -C bundled && rm bundled/*.tar.gz && mv bundled/portainer-mcp bundled/portainer-mcp-linux-amd64 2>/dev/null || echo "  Skipped (not available)"
	@echo "Linux ARM64..."
	curl -sL -o bundled/portainer-mcp-linux-arm64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-linux-arm64.tar.gz && \
		tar -xzf bundled/portainer-mcp-linux-arm64.tar.gz -C bundled && rm bundled/*.tar.gz && mv bundled/portainer-mcp bundled/portainer-mcp-linux-arm64 2>/dev/null || echo "  Skipped (not available)"
	@echo "macOS ARM64 (Apple Silicon)..."
	curl -sL -o bundled/portainer-mcp-darwin-arm64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-darwin-arm64.tar.gz && \
		tar -xzf bundled/portainer-mcp-darwin-arm64.tar.gz -C bundled && rm bundled/*.tar.gz && mv bundled/portainer-mcp bundled/portainer-mcp-darwin-arm64 2>/dev/null || echo "  Skipped (not available)"
	@echo "Note: Windows and macOS Intel binaries not available from portainer-mcp project"
	ls -la bundled/

run: build
	./$(BINARY) -portainer-url $(PORTAINER_URL) -portainer-token $(PORTAINER_TOKEN)