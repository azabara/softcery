# Start from a base image with Go installed
FROM golang:1.17-alpine AS builder

# Set the current working directory inside the container
WORKDIR /app

# Copy the Go module files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy the rest of the application source code
COPY . .

# Build the Go application
RUN go build -o /app/server .

# Start a new stage
FROM alpine:latest

# Set the working directory to /app in the new stage
WORKDIR /app

# Copy the compiled executable from the builder stage to the new stage
COPY --from=builder /app/server .

# Expose port 8080
EXPOSE 8080

# Command to run the server
CMD ["./server"]
