GO ?= go
GOLANGCILINT ?= golangci-lint

BINARY := oauth2-proxy
VERSION ?= $(shell git describe --always --dirty --tags 2>/dev/null || echo "undefined")
# Allow to override image registry.
REGISTRY ?= axelvanraes
IMAGE_NAME ?= oauth2-proxy-streamlit
.NOTPARALLEL:

GO_MAJOR_VERSION = $(shell $(GO) version | cut -c 14- | cut -d' ' -f1 | cut -d'.' -f1)
GO_MINOR_VERSION = $(shell $(GO) version | cut -c 14- | cut -d' ' -f1 | cut -d'.' -f2)
MINIMUM_SUPPORTED_GO_MAJOR_VERSION = 1
MINIMUM_SUPPORTED_GO_MINOR_VERSION = 15
GO_VERSION_VALIDATION_ERR_MSG = Golang version is not supported, please update to at least $(MINIMUM_SUPPORTED_GO_MAJOR_VERSION).$(MINIMUM_SUPPORTED_GO_MINOR_VERSION)

ifeq ($(COVER),true)
TESTCOVER ?= -coverprofile c.out
endif

.PHONY: all
all: lint $(BINARY)

.PHONY: clean
clean:
	-rm -rf release
	-rm -f $(BINARY)

.PHONY: distclean
distclean: clean
	rm -rf vendor

.PHONY: lint
lint: validate-go-version
	GO111MODULE=on $(GOLANGCILINT) run

.PHONY: build
build: validate-go-version clean $(BINARY)

$(BINARY):
	CGO_ENABLED=0 $(GO) build -a -installsuffix cgo -ldflags="-X main.VERSION=${VERSION}" -o $@ github.com/oauth2-proxy/oauth2-proxy/v7

DOCKER_BUILD_PLATFORM ?= linux/amd64,linux/arm64,linux/arm/v6
DOCKER_BUILDX_ARGS ?=
DOCKER_BUILD := docker build --build-arg VERSION=${VERSION}
DOCKER_BUILDX := docker buildx build ${DOCKER_BUILDX_ARGS} --platform ${DOCKER_BUILD_PLATFORM} --build-arg VERSION=${VERSION}

.PHONY: docker
docker:
	$(DOCKER_BUILDX) -f Dockerfile -t $(REGISTRY)/${IMAGE_NAME}:latest .

.PHONY: docker-all
docker-all: docker
	$(DOCKER_BUILD) -f Dockerfile -t $(REGISTRY)/${IMAGE_NAME}:latest-amd64 .
	$(DOCKER_BUILD) -f Dockerfile -t $(REGISTRY)/${IMAGE_NAME}:${VERSION} .
	$(DOCKER_BUILD) -f Dockerfile -t $(REGISTRY)/${IMAGE_NAME}:${VERSION}-amd64 .
	$(DOCKER_BUILD) -f Dockerfile.arm64 -t $(REGISTRY)/${IMAGE_NAME}:latest-arm64 .
	$(DOCKER_BUILD) -f Dockerfile.arm64 -t $(REGISTRY)/${IMAGE_NAME}:${VERSION}-arm64 .
	$(DOCKER_BUILD) -f Dockerfile.armv6 -t $(REGISTRY)/${IMAGE_NAME}:latest-armv6 .
	$(DOCKER_BUILD) -f Dockerfile.armv6 -t $(REGISTRY)/${IMAGE_NAME}:${VERSION}-armv6 .

.PHONY: docker-push
docker-push:
	docker buildx build --push --platform ${DOCKER_BUILD_PLATFORM} -t $(REGISTRY)/${IMAGE_NAME}:latest .

.PHONY: docker-push-all
docker-push-all: docker-push
	docker push $(REGISTRY)/${IMAGE_NAME}:latest-amd64
	docker push $(REGISTRY)/${IMAGE_NAME}:${VERSION}
	docker push $(REGISTRY)/${IMAGE_NAME}:${VERSION}-amd64
	docker push $(REGISTRY)/${IMAGE_NAME}:latest-arm64
	docker push $(REGISTRY)/${IMAGE_NAME}:${VERSION}-arm64
	docker push $(REGISTRY)/${IMAGE_NAME}:latest-armv6
	docker push $(REGISTRY)/${IMAGE_NAME}:${VERSION}-armv6

.PHONY: generate
generate:
	go generate ./pkg/...

.PHONY: verify-generate
verify-generate: generate
	git diff --exit-code

.PHONY: test
test: lint
	GO111MODULE=on $(GO) test $(TESTCOVER) -v -race ./...

.PHONY: release
release: validate-go-version lint test
	BINARY=${BINARY} VERSION=${VERSION} ./dist.sh

.PHONY: validate-go-version
validate-go-version:
	@if [ $(GO_MAJOR_VERSION) -gt $(MINIMUM_SUPPORTED_GO_MAJOR_VERSION) ]; then \
		exit 0 ;\
	elif [ $(GO_MAJOR_VERSION) -lt $(MINIMUM_SUPPORTED_GO_MAJOR_VERSION) ]; then \
		echo '$(GO_VERSION_VALIDATION_ERR_MSG)';\
		exit 1; \
	elif [ $(GO_MINOR_VERSION) -lt $(MINIMUM_SUPPORTED_GO_MINOR_VERSION) ] ; then \
		echo '$(GO_VERSION_VALIDATION_ERR_MSG)';\
		exit 1; \
	fi

# local-env can be used to interact with the local development environment
# eg:
#    make local-env-up 					# Bring up a basic test environment
#    make local-env-down 				# Tear down the basic test environment
#    make local-env-nginx-up 		# Bring up an nginx based test environment
#    make local-env-nginx-down 	# Tead down the nginx based test environment
.PHONY: local-env-%
local-env-%:
	make -C contrib/local-environment $*
