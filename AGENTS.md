# Portainer MCP HTTP Server - Build & Release Guide

This document describes how to build binaries, create GitHub releases, and publish Docker packages.

## Prerequisites

- Go 1.24+
- Docker with buildx support
- GitHub CLI (`gh`)
- Make

## Supported Architectures

Based on [portainer-mcp releases](https://github.com/portainer/portainer-mcp/releases), we support:

- **Linux**: amd64, arm64
- **macOS**: arm64 (Apple Silicon)
- **Windows**: Not supported (portainer-mcp doesn't provide Windows binaries)

## Build Binaries

### 1. Download portainer-mcp binaries

```bash
make download-mcp-bundled
```

This downloads the required `portainer-mcp` binaries to the `bundled/` directory.

### 2. Build all platform binaries

```bash
make release
```

This creates binaries in `dist/`:
- `portainer-mcp-server-linux-amd64`
- `portainer-mcp-server-linux-arm64`
- `portainer-mcp-server-darwin-arm64`

### 3. Build single binary (local development)

```bash
make build
```

Creates `./portainer-mcp-server` for current platform.

## Create GitHub Release

### 1. Ensure you're on main branch with clean state

```bash
git checkout main
git pull origin main
```

### 2. Update VERSION in Makefile (if needed)

Edit `Makefile` and update:
```makefile
VERSION := v0.7.0
PORTAINER_MCP_VERSION := v0.7.0
```

### 3. Commit any changes

```bash
git add .
git commit -m "release: v0.7.0"
git push origin main
```

### 4. Tag the release

```bash
git tag -d v0.7.0  # Delete old tag if exists
git tag v0.7.0
git push origin v0.7.0 --force
```

### 5. Create GitHub release with binaries

```bash
# Create release
gh release create v0.7.0 --title "v0.7.0" --notes "Initial release"

# Upload binaries
gh release upload v0.7.0 dist/portainer-mcp-server-linux-amd64 --clobber
gh release upload v0.7.0 dist/portainer-mcp-server-linux-arm64 --clobber
gh release upload v0.7.0 dist/portainer-mcp-server-darwin-arm64 --clobber
```

Or all at once:
```bash
for file in dist/portainer-mcp-server-*; do
    gh release upload v0.7.0 "$file" --clobber
done
```

### 6. Delete and recreate release (if needed)

```bash
gh release delete v0.7.0 --yes
# Then repeat steps 4-5
```

## Build and Push Docker Images

### 1. Ensure Docker buildx is set up

```bash
# Check if buildx is available
docker buildx version

# Create a builder instance if needed
docker buildx create --use --name multiplatform
```

### 2. Login to GitHub Container Registry

```bash
gh auth token | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

### 3. Build and push multi-platform images

```bash
# For production release
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/1buck/portainer-mcp-server:v0.7.0 \
  -t ghcr.io/1buck/portainer-mcp-server:latest \
  --push .
```

### 4. Build without pushing (local testing)

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t portainer-mcp-server:test .
```

### 5. Rebuild with no cache (if needed)

```bash
docker buildx build --no-cache \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/1buck/portainer-mcp-server:v0.7.0 \
  -t ghcr.io/1buck/portainer-mcp-server:latest \
  --push .
```

## Delete and Rebuild Everything

### 1. Clean local build artifacts

```bash
make clean
```

### 2. Delete GitHub release

```bash
gh release delete v0.7.0 --yes
```

### 3. Delete and recreate git tag

```bash
git tag -d v0.7.0
git push origin :refs/tags/v0.7.0
git tag v0.7.0
git push origin v0.7.0
```

### 4. Full rebuild and release

```bash
# Clean and rebuild
make clean
make release

# Create release
gh release create v0.7.0 --title "v0.7.0" --notes "Initial release"
for file in dist/portainer-mcp-server-*; do
    gh release upload v0.7.0 "$file" --clobber
done

# Build and push Docker
docker buildx build --no-cache \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/1buck/portainer-mcp-server:v0.7.0 \
  -t ghcr.io/1buck/portainer-mcp-server:latest \
  --push .
```

## Verify Releases

### Check GitHub release

```bash
gh release view v0.7.0
```

### Check Docker image

```bash
# Inspect manifest
docker buildx imagetools inspect ghcr.io/1buck/portainer-mcp-server:v0.7.0

# Pull and test
docker pull ghcr.io/1buck/portainer-mcp-server:v0.7.0
docker run --rm ghcr.io/1buck/portainer-mcp-server:v0.7.0 --help
```

## Troubleshooting

### Docker push fails with 403

Ensure you're logged in:
```bash
gh auth token | docker login ghcr.io -u USERNAME --password-stdin
```

### Binary exec format error

The `portainer-mcp` binary requires glibc. We use `debian:bookworm-slim` as the base image instead of Alpine for compatibility.

### Missing portainer-mcp binary

The Dockerfile downloads `portainer-mcp` at build time. If download fails, check:
- `PORTAINER_MCP_VERSION` matches an existing release
- Network connectivity to GitHub

## Notes

- **Darwin/macOS**: We only provide standalone binaries for macOS (darwin-arm64), not Docker images. Docker Desktop on Mac runs Linux containers.
- **Version matching**: Ensure `PORTAINER_MCP_VERSION` in Makefile matches the version you want to support.
- **GitHub Packages**: Docker images are published to GitHub Container Registry (ghcr.io).
