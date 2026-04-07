# Build stage - native compilation for each platform
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git curl tar

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build for target architecture using cross-compilation
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o portainer-mcp-server .

# Final stage - use debian for glibc compatibility
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl tar && rm -rf /var/lib/apt/lists/*

# Download portainer-mcp binary for the target platform
ARG TARGETARCH
ARG PORTAINER_MCP_VERSION=v0.7.0
RUN mkdir -p /usr/local/bin && \
    curl -sL -o /tmp/portainer-mcp.tar.gz \
    https://github.com/portainer/portainer-mcp/releases/download/${PORTAINER_MCP_VERSION}/portainer-mcp-${PORTAINER_MCP_VERSION}-linux-${TARGETARCH}.tar.gz && \
    tar -xzf /tmp/portainer-mcp.tar.gz -C /usr/local/bin && \
    rm /tmp/portainer-mcp.tar.gz && \
    chmod +x /usr/local/bin/portainer-mcp

COPY --from=builder /app/portainer-mcp-server /usr/local/bin/

EXPOSE 8080

ENTRYPOINT ["portainer-mcp-server"]