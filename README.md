# Portainer MCP HTTP Server

An HTTP wrapper for [portainer-mcp](https://github.com/portainer/portainer-mcp) that exposes MCP via SSE (Server-Sent Events), allowing mobile apps and web clients to connect.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              Connection Architecture                              │
│                                                                                   │
│  ┌─────────────────┐                                                             │
│  │    Client       │                                                             │
│  │  (Kontainer)    │                                                             │
│  │                 │                                                             │
│  │  ┌───────────┐  │                                                             │
│  │  │ McpClient │  │                                                             │
│  │  │           │  │                                                             │
│  │  │ HTTP/SSE  │──┼─────────────────────────────────────────────────────────────│
│  │  │ Auth:     │  │     HTTP Basic Auth (password)                              │
│  │  │ password  │  │     SSE: GET /sse                                           │
│  │  └───────────┘  │     Msg: POST /mcp/message                                  │
│  └─────────────────┘                                                             │
│           │                                                                       │
│           │ HTTPS                                                                 │
│           │                                                                       │
│           ▼                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                      portainer-mcp-server (Go)                              │ │
│  │                                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                        HTTP Server (:8080)                           │   │ │
│  │  │                                                                     │   │ │
│  │  │  Endpoints:                                                         │   │ │
│  │  │  • /sse         GET   SSE stream, creates MCP session               │   │ │
│  │  │  • /mcp/message POST  Send JSON-RPC to MCP                          │   │ │
│  │  │  • /connect    GET   Test Portainer connectivity                    │   │ │
│  │  │  • /health     GET   Health check (no auth)                         │   │ │
│  │  │                                                                     │   │ │
│  │  │  Auth: HTTP Basic Auth (password flag)                              │   │ │
│  │  └─────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                      MCPSession Manager                              │   │ │
│  │  │                                                                     │   │ │
│  │  │  • Spawns portainer-mcp process per SSE connection                  │   │ │
│  │  │  • Communicates via stdin/stdout (JSON-RPC)                         │   │ │
│  │  │  • Maps SSE events to MCP responses                                 │   │ │
│  │  │  • Session cleanup on disconnect                                    │   │ │
│  │  └─────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│           │                                                                       │
│           │ stdio (stdin/stdout)                                                  │
│           │ JSON-RPC messages                                                     │
│           │                                                                       │
│           ▼                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                      portainer-mcp (Node.js)                               │ │
│  │                                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                     MCP Protocol Server                              │   │ │
│  │  │                                                                     │   │ │
│  │  │  • Implements MCP specification (2024-11-05)                        │   │ │
│  │  │  • Exposes Portainer tools:                                         │   │ │
│  │  │    - list_containers, get_container, start/stop/remove              │   │ │
│  │  │    - list_images, pull_image, remove_image                          │   │ │
│  │  │    - list_volumes, create_volume, remove_volume                     │   │ │
│  │  │    - list_networks, create_network, remove_network                  │   │ │
│  │  │    - list_stacks, deploy_stack, remove_stack                        │   │ │
│  │  │    - Kubernetes: namespaces, pods, deployments, services            │   │ │
│  │  │                                                                     │   │ │
│  │  │  Args:                                                               │   │ │
│  │  │  -server <url>      Portainer URL                                   │   │ │
│  │  │  -token <token>     Portainer API token                             │   │ │
│  │  │  -read-only         Disable write operations                        │   │ │
│  │  └─────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│           │                                                                       │
│           │ HTTPS REST API                                                        │
│           │ X-API-Key header                                                      │
│           │                                                                       │
│           ▼                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                         Portainer Instance                                 │ │
│  │                                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                      Portainer Server                                │   │ │
│  │  │                                                                     │   │ │
│  │  │  • Manages Docker/Kubernetes environments                           │   │ │
│  │  │  • API endpoints:                                                   │   │ │
│  │  │    - /api/status          System info                               │   │ │
│  │  │    - /api/endpoints       List environments                         │   │ │
│  │  │    - /api/docker/...       Docker operations                        │   │ │
│  │  │    - /api/kubernetes/...   Kubernetes operations                    │   │ │
│  │  │                                                                     │   │ │
│  │  │  Auth: API Token (X-API-Key)                                        │   │ │
│  │  └─────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                     Environments                                     │   │ │
│  │  │                                                                     │   │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐ │   │ │
│  │  │  │  Docker      │  │  Docker      │  │     Kubernetes             │ │   │ │
│  │  │  │  Standalone  │  │   Swarm      │  │   (K3s, EKS, GKE, AKS...) │ │   │ │
│  │  │  │              │  │              │  │                            │ │   │ │
│  │  │  │  Containers  │  │  Services    │  │  Namespaces                │ │   │ │
│  │  │  │  Images      │  │  Stacks      │  │  Deployments               │ │   │ │
│  │  │  │  Volumes     │  │  Networks    │  │  Pods                      │ │   │ │
│  │  │  │  Networks    │  │              │  │  Services                  │ │   │ │
│  │  │  └──────────────┘  └──────────────┘  └────────────────────────────┘ │   │ │
│  │  └─────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Connection Flow

```
1. Client connects via SSE
   GET /sse (with Basic Auth)
   
2. Server creates MCP session
   └─> Spawns portainer-mcp process
   └─> Sends "endpoint" event with message URL
   
3. Client initializes MCP protocol
   POST /mcp/message
   { "method": "initialize", "params": { ... } }
   
4. MCP tools discovery
   { "method": "tools/list" }
   └─> Returns available Portainer tools
   
5. Tool execution
   { "method": "tools/call", "params": { "name": "list_containers" } }
   └─> portainer-mcp calls Portainer API
   └─> Response streamed via SSE
```

### Data Flow

| Stage | Protocol | Transport |
|-------|----------|-----------|
| Client → MCP Server | MCP over SSE | HTTPS |
| MCP Server → portainer-mcp | JSON-RPC | stdio |
| portainer-mcp → Portainer | REST API | HTTPS |

## Prerequisites

1. Download `portainer-mcp` binary from [releases](https://github.com/portainer/portainer-mcp/releases)
2. Place it in your PATH or specify with `-mcp-path`

## Installation

### From Source

```bash
go build -o portainer-mcp-server .
```

### Download Binary

Download from releases page (coming soon).

## Usage

### Basic Usage (HTTPS, auto-detected)

```bash
./portainer-mcp-server \
  -portainer-url portainer.example.com \
  -portainer-token YOUR_API_TOKEN \
  -password YOUR_PASSWORD \
  -listen :8080 \
  -base-url https://mcp.example.com
```

### With IP Address and Port

```bash
./portainer-mcp-server \
  -portainer-url 192.168.1.100:9443 \
  -portainer-token YOUR_API_TOKEN \
  -password YOUR_PASSWORD
```

### Using HTTP (for local development)

```bash
./portainer-mcp-server \
  -portainer-url localhost:9000 \
  -portainer-token YOUR_API_TOKEN \
  -password YOUR_PASSWORD \
  -use-http
```

### Full URL (scheme preserved)

```bash
./portainer-mcp-server \
  -portainer-url https://portainer.example.com:9443 \
  -portainer-token YOUR_API_TOKEN \
  -password YOUR_PASSWORD
```

### URL Format Support

The `-portainer-url` flag accepts multiple formats:

| Format | Example | Result |
|--------|---------|--------|
| Hostname only | `portainer.example.com` | `https://portainer.example.com` |
| IP address | `192.168.1.100` | `https://192.168.1.100` |
| IP with port | `192.168.1.100:9443` | `https://192.168.1.100:9443` |
| Localhost with port | `localhost:9000` | `https://localhost:9000` |
| Full HTTPS URL | `https://portainer.example.com` | Unchanged |
| Full HTTP URL | `http://localhost:9000` | Unchanged |
| With `--use-http` | `portainer.example.com` | `http://portainer.example.com` |

### Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-portainer-url` | Portainer server URL (hostname, IP:port, or full URL) | - |
| `-portainer-token` | Portainer API token (required) | - |
| `-password` | Password for HTTP Basic Auth (required) | - |
| `-use-http` | Use HTTP instead of HTTPS | `false` |
| `-mcp-path` | Path to portainer-mcp binary | `portainer-mcp` |
| `-listen` | Listen address | `:8080` |
| `-base-url` | Base URL for SSE endpoint | auto from Host header |
| `-read-only` | Enable read-only mode | `false` |
| `-skip-version-check` | Skip Portainer version check | `false` |
| `-debug` | Enable debug logging | `false` |

## Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/sse` | GET | Required | SSE endpoint for MCP communication |
| `/mcp/message` | POST | Required | Send JSON-RPC messages |
| `/connect` | GET | Required | Test connection to Portainer |
| `/health` | GET | None | Health check |

### `/connect` - Connection Test

Use this endpoint to validate the connection before saving configuration. Returns JSON:

**Success Response:**
```json
{
  "success": true,
  "message": "Connection successful",
  "version": "2.19.4"
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "Invalid Portainer API token"
}
```

This endpoint tests connectivity to the Portainer server by calling `/api/status` with the configured API token. Use it in your app's "Add MCP Server" screen to let users verify credentials before saving.

## Connecting from Kontainer App

1. Run this server on your infrastructure
2. In the app, add a new MCP server with:
   - **URL**: `https://your-server.com/sse`
   - **Password**: Password configured for the MCP server (required)

## Docker

```dockerfile
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o portainer-mcp-server .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/portainer-mcp-server /usr/local/bin/
COPY --from=portainer/portainer-mcp:latest /usr/local/bin/portainer-mcp /usr/local/bin/
EXPOSE 8080
CMD ["portainer-mcp-server"]
```

## Docker Compose

```yaml
version: '3.8'
services:
  portainer-mcp-server:
    build: .
    ports:
      - "8080:8080"
    environment:
      - PORTAINER_URL=https://portainer.example.com
      - PORTAINER_TOKEN=your-token-here
      - MCP_PASSWORD=your-password-here
    command:
      - -portainer-url
      - ${PORTAINER_URL}
      - -portainer-token
      - ${PORTAINER_TOKEN}
      - -password
      - ${MCP_PASSWORD}
      - -listen
      - :8080
```

## License

MIT