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
  -e MCP_BASE_URL=192.168.1.50:8080 \
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
      - MCP_BASE_URL=192.168.1.50:8080
```

### Option 4: Build from Source

```bash
git clone https://github.com/1buck/portainer-mcp-http-server.git
cd portainer-mcp-http-server
go build -o portainer-mcp-server .
```

## Usage

### Binary

After downloading or building, run:

```bash
# Basic usage
./portainer-mcp-server \
  -portainer-url http://localhost:9000 \
  -portainer-token YOUR_TOKEN \
  -password YOUR_PASSWORD \
  -base-url 192.168.1.50:8080
```
### Docker / Docker Compose

Environment variables map to flags:

| Environment Variable | Flag | Example |
|---------------------|------|---------|
| `PORTAINER_URL` | `-portainer-url` | `http://portainer:9000` |
| `PORTAINER_TOKEN` | `-portainer-token` | Your API token |
| `MCP_PASSWORD` | `-password` | Your password |
| `MCP_BASE_URL` | `-base-url` | `192.168.1.50:8080` |
| `MCP_LISTEN` | `-listen` | `:8080` |
| `MCP_READ_ONLY` | `-read-only` | `true` or `false` |

## Configuration

### Required Flags

| Flag | Description | Example |
|------|-------------|---------|
| `-portainer-url` | Your Portainer URL | `portainer.example.com` or `192.168.1.100:9443` |
| `-portainer-token` | Portainer API token | Get from Portainer → Settings → API Tokens |
| `-password` | Password for app authentication | Any password you choose |

### Optional Flags

| Flag | Description | Default | Env Variable |
|------|-------------|---------|--------------|
| `-listen` | Server listen address | `:8080` | `MCP_LISTEN` |
| `-base-url` | **Public URL for QR code and SSE** (e.g., `192.168.1.100:8080`, hostname, or full URL) | Auto-detected from hostname | `MCP_BASE_URL` |
| `-read-only` | Disable write operations | `false` | `MCP_READ_ONLY` |
| `-use-http` | Use HTTP (dev only) | `false` | - |
| `-debug` | Enable debug logs | `false` | - |

## Connecting from Kontainer App

1. Start server
2. In Kontainer app
   - Go to instance setting screen
   - Scan QR code generated in console or manually input url and password
3. Test and save connnection

<img src="assets/screenshot.png" alt="scan qr in kontainer app" style="width:150px;"/>




### Download Kontainer App
* Android: https://play.google.com/store/apps/details?id=com.devculi.kontainer
* IOS: https://apps.apple.com/us/app/portainer/id6742278087

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.devculi.kontainer">
    <img src="assets/google-play.svg" alt="Download from Google Play Store" style="width:150px;"/>
  </a>
  <a href="https://apps.apple.com/us/app/portainer/id6742278087">
    <img src="assets/apple.svg" alt="Download from Apple App Store" style="width:150px;"/>
  </a>
</p>


## License

MIT
