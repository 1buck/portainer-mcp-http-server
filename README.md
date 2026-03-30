# Portainer MCP HTTP Server

It's just a wrapper of [portainer-mcp](https://github.com/portainer/portainer-mcp) that allows you to access Portainer via an HTTP client.

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          YOUR INFRASTRUCTURE                                 │
│                                                                              │
│   Kontainer App                  portainer-mcp-server         Portainer     │
│   (your phone)                   (your server)                (your server) │
│                                                                              │
│   ┌─────────────┐                ┌────────────────────┐      ┌───────────┐ │
│   │             │   HTTPS/SSE    │                    │      │           │ │
│   │  Connect    │───────────────▶│  Receive requests  │─────▶│  Docker   │ │
│   │             │                │  Forward to MCP    │      │  Swarm    │ │
│   │  Control    │◀───────────────│  Return results    │◀─────│  K8s      │ │
│   │             │   Responses    │                    │      │           │ │
│   └─────────────┘                └────────────────────┘      └───────────┘ │
│                                                                              │
│   ● Your data stays on your servers                                          │
│   ● Your credentials never leave your infrastructure                         │
│   ● No third-party services involved                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **You run the server** on your machine/VPS next to Portainer
2. **App connects** to your server with password authentication
3. **Server forwards** requests to Portainer via MCP
4. **Results return** directly to your app

Your Portainer API token and password never leave your infrastructure.

## Installation

### Option 1: Download Binary

Download from [GitHub Releases](https://github.com/1buck/portainer-mcp-http-server/releases):

| Platform | File |
|----------|------|
| Linux (amd64) | `portainer-mcp-server-linux-amd64` |
| Linux (arm64) | `portainer-mcp-server-linux-arm64` |
| macOS (Intel) | `portainer-mcp-server-darwin-amd64` |
| macOS (Apple Silicon) | `portainer-mcp-server-darwin-arm64` |
| Windows | `portainer-mcp-server-windows-amd64.exe` |

### Option 2: Docker

```bash
docker run -d \
  -p 8080:8080 \
  -e PORTAINER_URL=https://portainer.example.com \
  -e PORTAINER_TOKEN=your-token \
  -e MCP_PASSWORD=your-password \
  ghcr.io/1buck/portainer-mcp-server:latest
```

### Option 3: Docker Compose

```yaml
version: '3.8'
services:
  portainer-mcp-server:
    image: ghcr.io/1buck/portainer-mcp-server:latest
    ports:
      - "8080:8080"
    environment:
      - PORTAINER_URL=https://portainer.example.com
      - PORTAINER_TOKEN=your-token
      - MCP_PASSWORD=your-password
```

### Option 4: Build from Source

```bash
git clone https://github.com/1buck/portainer-mcp-http-server.git
cd portainer-mcp-http-server
go build -o portainer-mcp-server .
```

## Usage

After downloading or building, run:

```bash
./portainer-mcp-server \
  -portainer-url portainer.example.com \
  -portainer-token YOUR_API_TOKEN \
  -password YOUR_PASSWORD
```

Your server is now ready at `http://localhost:8080`.

## Configuration

### Required Flags

| Flag | Description | Example |
|------|-------------|---------|
| `-portainer-url` | Your Portainer URL | `portainer.example.com` or `192.168.1.100:9443` |
| `-portainer-token` | Portainer API token | Get from Portainer → Settings → API Tokens |
| `-password` | Password for app authentication | Any password you choose |

### Optional Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-listen` | Server listen address | `:8080` |
| `-base-url` | Public URL for SSE endpoint | Auto-detected |
| `-read-only` | Disable write operations | `false` |
| `-use-http` | Use HTTP (dev only) | `false` |
| `-debug` | Enable debug logs | `false` |

### URL Formats

All these work:

```bash
# Hostname (HTTPS assumed)
-portainer-url portainer.example.com

# IP with port
-portainer-url 192.168.1.100:9443

# Full URL
-portainer-url https://portainer.example.com:9443

# Local development
-portainer-url localhost:9000 -use-http
```

## Getting Your Portainer Token

1. Open Portainer web UI
2. Go to **Settings → API Tokens**
3. Click **Add API token**
4. Give it a name (e.g., "kontainer")
5. Copy the generated token

## Connecting Kontainer App

1. Ensure server is running
2. In Kontainer app, add new MCP server:
   - **URL**: `https://your-server.com/sse` (or `http://localhost:8080/sse` for local)
   - **Password**: The password you set with `-password` flag
3. App will discover available tools automatically

## Health Check

```bash
curl http://localhost:8080/health
# Returns: OK
```

## Test Connection

```bash
curl -u :your-password http://localhost:8080/connect
# Returns: {"success": true, "version": "2.19.4"}
```

Use this to verify your Portainer URL and token before saving in the app.

## Security Best Practices

1. **Run behind HTTPS** - Use reverse proxy (nginx, Traefik, Caddy) with SSL
2. **Strong password** - Use a unique, strong password for `-password`
3. **Restrict Portainer token** - Create token with minimal required permissions
4. **Read-only mode** - Use `-read-only` if you only need monitoring
5. **Firewall** - Restrict access to known IPs if possible

### Example with Caddy (automatic HTTPS)

```caddyfile
mcp.example.com {
    reverse_proxy localhost:8080
}
```

### Example with nginx

```nginx
server {
    listen 443 ssl;
    server_name mcp.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Available Operations

Once connected, Kontainer can:

- **Containers**: list, get details, start, stop, restart, remove
- **Images**: list, pull, remove
- **Volumes**: list, create, remove
- **Networks**: list, create, remove
- **Stacks**: list, deploy, remove (Docker Swarm)
- **Kubernetes**: namespaces, pods, deployments, services, logs

## Troubleshooting

### "Unauthorized" error

- Check password matches exactly what you set
- Ensure app is using correct URL

### "Connection failed" error

- Verify Portainer URL is reachable from server
- Check API token is valid (test with `/connect` endpoint)
- Ensure Portainer is running

### "Streaming unsupported" error

- Server doesn't support SSE. Use a proper HTTP server.

## Requirements

- Portainer CE or BE 2.0+
- `portainer-mcp` binary (bundled in Docker image, or download separately)

## License

MIT
