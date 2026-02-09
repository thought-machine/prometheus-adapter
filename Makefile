IMAGE=prometheus-adapter
ARCH?=$(shell go env GOARCH)
ALL_ARCH=amd64 arm arm64 ppc64le s390x
GOPATH := $(shell echo $(GOPATH) | cut -d: -f1)

VERSION=$(shell cat VERSION)
TAG_PREFIX=v
TAG?=$(TAG_PREFIX)$(VERSION)

GO_VERSION?=$(shell grep -E '^go [0-9.]+' go.mod | awk '{print $$2}')
GOLANGCI_VERSION?=2.8.0

.PHONY: all
all: prometheus-adapter

# Build
# -----

SRC_DEPS=$(shell find pkg cmd -type f -name "*.go")

prometheus-adapter: $(SRC_DEPS)
	CGO_ENABLED=0 GOARCH=$(ARCH) go build github.com/thought-machine/prometheus-adapter/cmd/adapter

.PHONY: container
container:
	docker build -t $(IMAGE)-$(ARCH):$(TAG) --build-arg ARCH=$(ARCH) --build-arg GO_VERSION=$(GO_VERSION) .

# Container push
# --------------

PUSH_ARCH_TARGETS=$(addprefix push-,$(ALL_ARCH))

.PHONY: push
push: container
	docker push $(IMAGE)-$(ARCH):$(TAG)

# Test
# ----

.PHONY: test
test:
	CGO_ENABLED=0 go test ./cmd/... ./pkg/...

.PHONY: test-e2e
test-e2e:
	./test/run-e2e-tests.sh


# Static analysis
# ---------------

.PHONY: verify
verify: verify-lint verify-deps verify-generated

.PHONY: update
update: update-lint update-generated

# Format and lint
# ---------------

HAS_GOLANGCI_VERSION:=$(shell $(GOPATH)/bin/golangci-lint version)
.PHONY: golangci
golangci:
ifneq ($(HAS_GOLANGCI_VERSION), $(GOLANGCI_VERSION))
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin v$(GOLANGCI_VERSION)
endif

.PHONY: verify-lint
verify-lint: golangci
	$(GOPATH)/bin/golangci-lint run --modules-download-mode=readonly || (echo 'Run "make update-lint"' && exit 1)

.PHONY: update-lint
update-lint: golangci
	$(GOPATH)/bin/golangci-lint run --fix --modules-download-mode=readonly


# Dependencies
# ------------

.PHONY: verify-deps
verify-deps:
	go mod verify
	go mod tidy
	@git diff --exit-code -- go.mod go.sum

# Generation
# ----------

generated_files=pkg/api/generated/openapi/zz_generated.openapi.go

.PHONY: verify-generated
verify-generated: update-generated
	@git diff --exit-code -- $(generated_files)

.PHONY: update-generated
update-generated:
	go install -mod=readonly k8s.io/kube-openapi/cmd/openapi-gen
	$(GOPATH)/bin/openapi-gen --logtostderr \
		--go-header-file ./hack/boilerplate.go.txt \
		--output-pkg ./pkg/api/generated/openapi \
		--output-file zz_generated.openapi.go \
		--output-dir ./pkg/api/generated/openapi \
		-r /dev/null \
		"k8s.io/metrics/pkg/apis/custom_metrics" "k8s.io/metrics/pkg/apis/custom_metrics/v1beta1" "k8s.io/metrics/pkg/apis/custom_metrics/v1beta2" "k8s.io/metrics/pkg/apis/external_metrics" "k8s.io/metrics/pkg/apis/external_metrics/v1beta1" "k8s.io/metrics/pkg/apis/metrics" "k8s.io/metrics/pkg/apis/metrics/v1beta1" "k8s.io/apimachinery/pkg/apis/meta/v1" "k8s.io/apimachinery/pkg/api/resource" "k8s.io/apimachinery/pkg/version" "k8s.io/api/core/v1"
