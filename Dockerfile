# Build stage — full toolchain required for CGO + SQLite
FROM golang:alpine AS builder
RUN apk add --no-cache gcc musl-dev sqlite-dev
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=1 GOOS=linux go build -ldflags="-w -s" -o hwid-server main.go

# Runtime stage — minimal image, no secrets baked in
FROM alpine:latest
RUN apk add --no-cache ca-certificates su-exec wget && \
    adduser -D -H -u 1001 appuser
WORKDIR /app
COPY --from=builder /app/hwid-server ./
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh && \
    mkdir -p /app/db && chown -R appuser:appuser /app
# Entrypoint may write private.pem as root then drop to appuser
USER root
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["/docker-entrypoint.sh"]
