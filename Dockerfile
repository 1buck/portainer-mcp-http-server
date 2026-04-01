# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o portainer-mcp-server .

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

ARG TARGETARCH
RUN wget -q https://github.com/portainer/portainer-mcp/releases/download/v0.7.0/portainer-mcp-v0.7.0-linux-${TARGETARCH}.tar.gz \
    && tar -xzf portainer-mcp-v0.7.0-linux-${TARGETARCH}.tar.gz \
    && mv portainer-mcp /usr/local/bin/ \
    && rm portainer-mcp-v0.7.0-linux-${TARGETARCH}.tar.gz

COPY --from=builder /app/portainer-mcp-server /usr/local/bin/

EXPOSE 8080

ENTRYPOINT ["portainer-mcp-server"]