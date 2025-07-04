# Multi-stage build for HTTP Media Server v2
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY *.go ./

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags '-extldflags "-static"' -o http-media-server .

# Final stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates tzdata

# Create non-root user
RUN addgroup -g 1000 -S mediaserver && \
    adduser -u 1000 -S mediaserver -G mediaserver

# Set working directory
WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/http-media-server .

# Copy default configuration
COPY config.yaml .

# Create media directory
RUN mkdir -p media && \
    chown -R mediaserver:mediaserver /app

# Switch to non-root user
USER mediaserver

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Set default command
CMD ["./http-media-server", "-config", "config.yaml"]
