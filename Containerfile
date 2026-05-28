# Distrobox-compatible development container for osac-workspace.
# Usage:
#   podman build -t osac-dev -f Containerfile .
#   distrobox create --image osac-dev --name osac --home /var/home/$USER
#   distrobox enter osac
#
# Inside the container, Claude Code and all dev tools are available.

FROM registry.fedoraproject.org/fedora:42

# Distrobox compatibility: install packages it expects on the host.
# See https://github.com/89luca89/distrobox/blob/main/docs/compatibility.md
RUN dnf install -y \
    bash \
    bc \
    bzip2 \
    curl \
    diffutils \
    dnf-plugins-core \
    findutils \
    git \
    gnupg2 \
    hostname \
    iproute \
    iputils \
    keyutils \
    less \
    lsof \
    man-db \
    man-pages \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    ncurses \
    nss-mdns \
    openssh-clients \
    openssl \
    passwd \
    pinentry \
    pigz \
    procps-ng \
    rsync \
    shadow-utils \
    sudo \
    tar \
    time \
    tree \
    unzip \
    util-linux \
    vte-profile \
    wget \
    which \
    words \
    xorg-x11-xauth \
    xz \
    zip \
    zsh \
    && dnf clean all

# --- Node.js (LTS, for Claude Code hooks and npm) ---
RUN dnf install -y nodejs npm && dnf clean all

# --- Go (latest stable for fulfillment-service / osac-operator) ---
ARG GO_VERSION=1.24.4
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    | tar -C /usr/local -xzf - \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# --- Go tools ---
RUN GOBIN=/usr/local/bin go install github.com/onsi/ginkgo/v2/ginkgo@latest

# --- buf (protobuf linting / codegen) ---
ARG BUF_VERSION=1.50.0
RUN curl -fsSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64.tar.gz" \
    | tar -C /usr/local -xzf - --strip-components=1 buf/bin/buf buf/bin/protoc-gen-buf-breaking buf/bin/protoc-gen-buf-lint

# --- kubectl ---
RUN curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# --- kind (Kubernetes in Docker, for integration tests) ---
ARG KIND_VERSION=0.27.0
RUN curl -fsSLo /usr/local/bin/kind \
    "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-linux-amd64" \
    && chmod +x /usr/local/bin/kind

# --- gh CLI (GitHub) ---
RUN dnf install -y 'dnf-command(config-manager)' \
    && dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo \
    && dnf install -y gh \
    && dnf clean all

# --- jira CLI (ankitpokhrel/jira-cli) ---
ARG JIRA_VERSION=1.7.0
RUN curl -fsSL "https://github.com/ankitpokhrel/jira-cli/releases/download/v${JIRA_VERSION}/jira_${JIRA_VERSION}_linux_x86_64.tar.gz" \
    | tar -C /usr/local/bin -xzf - --strip-components=2 --wildcards '*/bin/jira' \
    && chmod +x /usr/local/bin/jira

# --- Python (for osac-test-infra, ansible) ---
RUN dnf install -y python3 python3-pip python3-pyyaml && dnf clean all
RUN pip3 install --no-cache-dir pytest ansible

# --- Claude Code ---
RUN npm install -g @anthropic-ai/claude-code

# --- make, gcc, etc. for cgo and Makefiles ---
RUN dnf install -y make gcc gcc-c++ && dnf clean all
