# Stage 1: Build the Go binary
FROM golang:1.17 AS builder

WORKDIR /

# Copy go.mod and go.sum to download dependencies
COPY app/*.* ./
RUN go mod download

# Copy the rest of the source code
COPY . .

# Build the Go binary
RUN go build -o server .

# Stage 2: Create a lightweight image with only the binary
FROM golang:1.17

WORKDIR /

# Copy the binary from the builder stage
COPY --from=builder /app/server .

# Expose port 8080
EXPOSE 8080

# Set the entry point
CMD ["./server"]
