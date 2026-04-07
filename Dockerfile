# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build for target architecture
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o portainer-mcp-server .

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

# Copy bundled portainer-mcp binary based on TARGETARCH
ARG TARGETARCH
COPY --from=builder /app/bundled/portainer-mcp-linux-${TARGETARCH} /usr/local/bin/portainer-mcp
RUN chmod +x /usr/local/bin/portainer-mcp

COPY --from=builder /app/portainer-mcp-server /usr/local/bin/

EXPOSE 8080

ENTRYPOINT ["portainer-mcp-server"]