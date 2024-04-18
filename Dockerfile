# Use the official golang image as the base image
FROM golang:latest AS builder

# Set the working directory inside the container
WORKDIR /app

RUN go get -u github.com/gin-gonic/gin
# Copy the Go module files
#COPY go.mod go.sum ./

# Download dependencies
#RUN go mod download

# Copy the rest of the source code
COPY . .

# Build the Go application
RUN go build -o /app/server .

# Use a minimal base image for the final container
FROM alpine:latest

# Set the working directory inside the container
WORKDIR /app

# Copy the binary from the builder stage to the final image
COPY --from=builder /app/server .

# Expose port 8080 to the outside world
EXPOSE 8080

# Command to run the server
CMD ["./server"]
