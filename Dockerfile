# Stage 1: Build the Go binary
FROM golang:alpine

WORKDIR /build

# Copy go.mod and go.sum to download dependencies
COPY *.* ./

# Build the Go binary
RUN go build -o server main.go

# Expose port 8080
EXPOSE 8080

# Set the entry point
CMD ["./server"]
