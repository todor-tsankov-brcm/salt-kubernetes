# syntax=docker/dockerfile:1
#
# Self-contained Salt minion image for salt-minion-kubernetes: core Salt plus
# saltext.vault and saltext.kubernetes, both pip-installed from PyPI.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG SALT_VERSION=3008.2
ARG SALT_UID=10001
ARG SALT_GID=10001
ARG SALT_HOME=/opt/saltstack/salt
ARG SALT_SHELL=/usr/sbin/nologin

ARG INCLUDE_KUBECTL=true
ARG KUBECTL_VERSION=v1.30.2
ARG TARGETARCH

ARG EXTRA_SALT_EXTENSIONS=""

ARG PIP_INDEX_URL=""
ARG PIP_TRUSTED_HOST=""
ARG PIP_ONLY_BINARY=""

ARG APT_MIRROR=""
ARG SALT_GPG_KEY_URL="https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public"
ARG SALT_APT_REPO_URL="https://packages.broadcom.com/artifactory/saltproject-deb"

LABEL org.opencontainers.image.title="Salt Minion"
LABEL org.opencontainers.image.description="Salt Minion runtime preloaded with saltext.vault and saltext.kubernetes, for RBAC-driven kube-bench compliance assessments"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# Adjust the Ubuntu apt mirror when APT_MIRROR is set.
RUN set -eu; \
    if [ -n "${APT_MIRROR}" ]; then \
        sed -i "s#^URIs: .*#URIs: ${APT_MIRROR}#" \
            /etc/apt/sources.list.d/ubuntu.sources; \
    fi

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        tini \
        iproute2 \
        dnsutils \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create the runtime identity before Salt assigns file ownership.
RUN groupadd --system --gid "${SALT_GID}" salt \
    && useradd --system --uid "${SALT_UID}" --gid "${SALT_GID}" \
        --no-create-home --home-dir "${SALT_HOME}" \
        --shell "${SALT_SHELL}" --comment Salt salt

# Install Salt through the official bootstrap script.
# build_ca is optional and is used only while downloading build dependencies.
RUN --mount=type=secret,id=build_ca,target=/tmp/build-ca.crt,required=false \
    set -eu; \
    if [ -s /tmp/build-ca.crt ]; then \
        cp /tmp/build-ca.crt \
            /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates; \
    fi; \
    curl -fsSL -o /tmp/bootstrap-salt.sh \
        https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh; \
    curl -fsSL -o /tmp/bootstrap-salt.sh.sha256 \
        https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh.sha256; \
    printf '%s  /tmp/bootstrap-salt.sh\n' \
        "$(cut -d' ' -f1 /tmp/bootstrap-salt.sh.sha256)" \
        > /tmp/bootstrap-salt.sh.sha256.check; \
    sha256sum -c /tmp/bootstrap-salt.sh.sha256.check; \
    if [ "${SALT_VERSION}" = "latest" ]; then \
        sh /tmp/bootstrap-salt.sh -X -P onedir; \
    else \
        sh /tmp/bootstrap-salt.sh -X -P onedir "${SALT_VERSION}"; \
    fi; \
    rm -f \
        /tmp/bootstrap-salt.sh \
        /tmp/bootstrap-salt.sh.sha256 \
        /tmp/bootstrap-salt.sh.sha256.check; \
    if [ -s /tmp/build-ca.crt ]; then \
        rm -f /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates >/dev/null; \
    fi

COPY salt-extensions.txt /tmp/salt-extensions.txt

# Install Salt extensions.
# hadolint ignore=DL3013
RUN --mount=type=secret,id=build_ca,target=/tmp/build-ca.crt,required=false \
    set -eu; \
    if [ -s /tmp/build-ca.crt ]; then \
        cp /tmp/build-ca.crt \
            /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates; \
    fi; \
    if [ -n "${PIP_INDEX_URL}" ]; then \
        set -- "$@" --index-url "${PIP_INDEX_URL}"; \
    fi; \
    if [ -n "${PIP_TRUSTED_HOST}" ]; then \
        set -- "$@" --trusted-host "${PIP_TRUSTED_HOST}"; \
    fi; \
    if [ -n "${PIP_ONLY_BINARY}" ]; then \
        set -- "$@" --only-binary "${PIP_ONLY_BINARY}"; \
    fi; \
    echo "Installing extensions from salt-extensions.txt using salt-pip..."; \
    salt-pip install --no-cache-dir "$@" \
        -r /tmp/salt-extensions.txt; \
    if [ -n "${EXTRA_SALT_EXTENSIONS}" ]; then \
        echo "Installing additional runtime extensions..."; \
        salt-pip install --no-cache-dir "$@" \
            ${EXTRA_SALT_EXTENSIONS}; \
    fi; \
    rm -f /tmp/salt-extensions.txt; \
    if [ -s /tmp/build-ca.crt ]; then \
        rm -f /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates >/dev/null; \
    fi

# Install kubectl when requested.
RUN --mount=type=secret,id=build_ca,target=/tmp/build-ca.crt,required=false \
    set -eu; \
    if [ -s /tmp/build-ca.crt ]; then \
        cp /tmp/build-ca.crt \
            /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates; \
    fi; \
    if [ "${INCLUDE_KUBECTL}" = "true" ]; then \
        curl -fsSL -o /usr/local/bin/kubectl \
            "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
        curl -fsSL -o /tmp/kubectl.sha256 \
            "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256"; \
        printf '%s  /usr/local/bin/kubectl\n' \
            "$(cat /tmp/kubectl.sha256)" \
            > /tmp/kubectl.sha256.check; \
        sha256sum -c /tmp/kubectl.sha256.check; \
        chmod 0755 /usr/local/bin/kubectl; \
        rm -f \
            /tmp/kubectl.sha256 \
            /tmp/kubectl.sha256.check; \
    fi; \
    if [ -s /tmp/build-ca.crt ]; then \
        rm -f /usr/local/share/ca-certificates/build-ca.crt; \
        update-ca-certificates >/dev/null; \
    fi

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p \
        /etc/salt/minion.d \
        /etc/salt/pki/minion \
        /etc/salt/pillar \
        /var/cache/salt/minion \
        /var/log/salt \
    && chown -R "${SALT_UID}:${SALT_GID}" \
        /etc/salt \
        /var/cache/salt \
        /var/log/salt

# hadolint ignore=DL3064
ENV SALT_MASTER="" \
    SALT_MASTER_PORT="4506" \
    SALT_PUBLISH_PORT="4505" \
    SALT_MASTER_PUBKEY_B64="" \
    SALT_MINION_ID="" \
    SALT_MASTER_FINGER="" \
    SALT_LOG_LEVEL="info" \
    VAULT_ADDR="" \
    VAULT_AUTH_METHOD="approle" \
    VAULT_ROLE_ID="" \
    VAULT_SECRET_ID="" \
    VAULT_SECRET_ID_FILE="" \
    VAULT_TOKEN="" \
    VAULT_TOKEN_FILE="" \
    VAULT_SDB_PROFILE="vault_sdb"

USER ${SALT_UID}:${SALT_GID}

VOLUME ["/etc/salt/pki/minion"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
