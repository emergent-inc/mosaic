BIN := mosaic-linux
VERSION ?= dev
LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: build test race e2e interop fmt clean cross

build:
	CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o $(BIN) ./cmd/mosaic-linux

test:
	go test ./...

race:
	go test -race ./...

# End-to-end test: spawns the built binary as host+viewer over real PTYs and
# an in-process relay, exercising the full wire path.
e2e: build
	MOSAIC_LINUX_BIN=$(CURDIR)/$(BIN) go test -count=1 ./e2e/

# Interop test against the DEPLOYED Mosaic relay (needs outbound network).
interop:
	MOSAIC_INTEROP=1 go test -run TestRealRelayRoundTrip -v ./relay/

fmt:
	gofmt -w .

# Release-style cross build for the common Linux targets.
cross:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BIN)-linux-amd64 ./cmd/mosaic-linux
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BIN)-linux-arm64 ./cmd/mosaic-linux

clean:
	rm -f $(BIN)
	rm -rf dist
