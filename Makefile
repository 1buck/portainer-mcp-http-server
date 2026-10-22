.PHONY: build test clean docker release run download-mcp-bundled

VERSION := 2.45.1
PORTAINER_MCP_VERSION := 2.45.1
BINARY := portainer-mcp-server
LDFLAGS := -ldflags="-s -w -X main.Version=$(VERSION)"

build:
	go build $(LDFLAGS) -o $(BINARY) .

test:
	go test -v ./...

clean:
	rm -f $(BINARY)
	rm -rf dist/
	rm -rf bundled/
	mkdir -p bundled
	touch bundled/.gitkeep

docker:
	docker build -t portainer-mcp-server .

release: clean download-mcp-bundled
	mkdir -p dist
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o dist/$(BINARY)-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o dist/$(BINARY)-linux-arm64 .
	GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o dist/$(BINARY)-darwin-arm64 .
	cp bundled/* dist/ 2>/dev/null || true

download-mcp-bundled:
	mkdir -p bundled
	@echo "Downloading portainer-mcp binaries for version $(PORTAINER_MCP_VERSION)..."
	@case "$(PORTAINER_MCP_VERSION)" in \
		v0.*) \
			echo "Downloading legacy v0.x tar.gz bundles..."; \
			echo "Linux AMD64..."; \
			curl -sL -o bundled/portainer-mcp-linux-amd64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-linux-amd64.tar.gz && \
				tar -xzf bundled/portainer-mcp-linux-amd64.tar.gz -C bundled && rm -f bundled/*.tar.gz && mv bundled/portainer-mcp bundled/portainer-mcp-linux-amd64 2>/dev/null || true; \
			echo "Linux ARM64..."; \
			curl -sL -o bundled/portainer-mcp-linux-arm64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-linux-arm64.tar.gz && \
				tar -xzf bundled/portainer-mcp-linux-arm64.tar.gz -C bundled && rm -f bundled/*.tar.gz && mv bundled/portainer-mcp bundled/portainer-mcp-linux-arm64 2>/dev/null || true; \
			echo "macOS ARM64..."; \
			curl -sL -o bundled/portainer-mcp-darwin-arm64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-darwin-arm64.tar.gz && \
				tar -xzf bundled/portainer-mcp-darwin-arm64.tar.gz -C bundled && rm -f bundled/*.tar.gz && mv bundled/portainer-mcp bundled/portainer-mcp-darwin-arm64 2>/dev/null || true; \
			;; \
		*) \
			echo "Downloading 2.x .mcpb bundles..."; \
			echo "Linux AMD64 (linux-x64.mcpb)..."; \
			curl -sL -o bundled/tmp-linux-x64.mcpb https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-linux-x64.mcpb && \
				unzip -p bundled/tmp-linux-x64.mcpb server/portainer-mcp > bundled/portainer-mcp-linux-amd64 && \
				chmod +x bundled/portainer-mcp-linux-amd64 && rm -f bundled/tmp-linux-x64.mcpb || echo "  Skipped linux-amd64"; \
			echo "macOS ARM64 (darwin-arm64.mcpb)..."; \
			curl -sL -o bundled/tmp-darwin-arm64.mcpb https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-darwin-arm64.mcpb && \
				unzip -p bundled/tmp-darwin-arm64.mcpb server/portainer-mcp > bundled/portainer-mcp-darwin-arm64 && \
				chmod +x bundled/portainer-mcp-darwin-arm64 && rm -f bundled/tmp-darwin-arm64.mcpb || echo "  Skipped darwin-arm64"; \
			echo "Linux ARM64 (fallback to v0.7.0)..."; \
			curl -sL -o bundled/tmp-linux-arm64.tar.gz https://github.com/portainer/portainer-mcp/releases/download/v0.7.0/portainer-mcp-v0.7.0-linux-arm64.tar.gz && \
				tar -xzf bundled/tmp-linux-arm64.tar.gz -C bundled && mv bundled/portainer-mcp bundled/portainer-mcp-linux-arm64 && \
				chmod +x bundled/portainer-mcp-linux-arm64 && rm -f bundled/tmp-linux-arm64.tar.gz || echo "  Skipped linux-arm64"; \
			echo "Windows AMD64 (win32-x64.mcpb)..."; \
			curl -sL -o bundled/tmp-win32-x64.mcpb https://github.com/portainer/portainer-mcp/releases/download/$(PORTAINER_MCP_VERSION)/portainer-mcp-$(PORTAINER_MCP_VERSION)-win32-x64.mcpb && \
				unzip -p bundled/tmp-win32-x64.mcpb server/portainer-mcp.exe > bundled/portainer-mcp-windows-amd64.exe && \
				rm -f bundled/tmp-win32-x64.mcpb || echo "  Skipped windows-amd64"; \
			;; \
	esac
	@touch bundled/.gitkeep
	ls -la bundled/

run: build
	./$(BINARY) -portainer-url $(PORTAINER_URL) -portainer-token $(PORTAINER_TOKEN)
