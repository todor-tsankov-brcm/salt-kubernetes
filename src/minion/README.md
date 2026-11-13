# Salt Minion Images for Kubernetes

This directory contains Dockerfiles for building Salt Minion images optimized for Kubernetes deployments. 

Two flavors are provided:

1. **Kubernetes Minion** (`kubernetes/`) - General-purpose minion with Kubernetes and Vault support
2. **VCF Minion** (`vcf/`) - VMware Cloud Foundation-specific extensions

## Kubernetes Minion

A Salt Minion Docker image built from the official Salt onedir distribution using Salt's [bootstrap script](https://github.com/saltstack/salt-bootstrap).

This minion is designed specifically for running inside Kubernetes clusters and includes:
- Support for in-cluster deployments via Kubernetes API
- Integration with Salt's Kubernetes execution module (`saltext.kubernetes`)
- HashiCorp Vault integration for secrets management (`saltext.vault`)
- Bundled `kubectl` for direct cluster interaction
- Support for CIS Kubernetes compliance assessments via kube-bench

The image:

- Uses Salt `3008.2` by default
- Runs as the non-root `salt` user with UID/GID `10000`
- Supports optional corporate CA during image build
- Does not retain build-time corporate CA in final image
- Communicates with Salt Master on ports `4505` (publish) and `4506` (request/return)
- Includes Docker health check
- Supports both self-generated and pre-seeded keypairs
- Enables secure multi-master connectivity

See [CHANGELOG.md](../../helm/salt-minion/CHANGELOG.md) for Salt versions in each image release.

### Build

From the root of the `salt-kubernetes` repository:

```bash
docker build \
  --platform linux/arm64 \
  --tag salt-minion:local \
  ./src/minion/kubernetes
```

### Build behind a corporate TLS proxy

If HTTPS downloads require a corporate root certificate:

```bash
# Export certificate
security find-certificate \
  -a \
  -c "Cloud Services Root CA" \
  -p \
  "${HOME}/Library/Keychains/login.keychain-db" \
  /Library/Keychains/System.keychain \
  /System/Library/Keychains/SystemRootCertificates.keychain \
  > /private/tmp/cloud-services-root-ca.crt

# Verify certificate
openssl x509 \
  -in /private/tmp/cloud-services-root-ca.crt \
  -noout \
  -subject \
  -issuer \
  -dates

# Build with certificate
docker build \
  --platform linux/arm64 \
  --secret id=build_ca,src=/private/tmp/cloud-services-root-ca.crt \
  --tag salt-minion:local \
  ./src/minion/kubernetes
```

### Build arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `SALT_VERSION` | `3008.2` | Salt version to install |

Example:

```bash
docker build \
  --platform linux/arm64 \
  --build-arg SALT_VERSION=3008.2 \
  --tag salt-minion:local \
  ./src/minion/kubernetes
```

### Verify the image

```bash
docker image inspect salt-minion:local \
  --format 'Image={{.RepoTags}} Architecture={{.Architecture}} OS={{.Os}}'
```

Expected on Apple Silicon Mac:

```text
Image=[salt-minion:local] Architecture=arm64 OS=linux
```

Verify Salt version:

```bash
docker run --rm \
  --platform linux/arm64 \
  salt-minion:local \
  salt-minion --version
```

Expected:

```text
salt-minion 3008.2 (Argon)
```

Verify runtime identity and permissions:

```bash
docker run --rm \
  --platform linux/arm64 \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c '
    id
    ls -ldn \
      /etc/salt \
      /etc/salt/minion.d \
      /etc/salt/pki \
      /var/cache/salt/minion
  '
```

Expected:

```text
uid=10000(salt) gid=10000(salt)
drwxr-xr-x  8 root      root  4096 Aug 15 20:31 /etc/salt
drwxr-xr-x  2 root      root  4096 Aug 15 20:31 /etc/salt/minion.d
drwxr-xr-x  4 root      root  4096 Aug 15 20:31 /etc/salt/pki
drwxr-xr-x  4 salt      salt  4096 Aug 15 20:31 /var/cache/salt/minion
```

### Run

Start Salt Minion connecting to a master:

```bash
docker run --rm \
  --name salt-minion \
  --env SALT_MASTER=salt-master.example.com \
  salt-minion:local
```

### Environment variables

The entrypoint translates these variables into minion configuration or uses them for key provisioning:

| Variable | Effect |
| --- | --- |
| `SALT_MASTER` | Sets master address (required for in_cluster mode). Can be comma-separated list for multi-master mode. |
| `SALT_MASTER_PORT` | Sets Salt request/return port. Default: `4506`. |
| `SALT_PUBLISH_PORT` | Sets Salt publish port. Default: `4505`. |
| `SALT_MINION_ID` | Sets minion ID. Pod hostname used if not supplied. |
| `SALT_MASTER_FINGER` | Sets master fingerprint for trust verification (legacy - use SALT_MASTER_PUBKEY_B64 instead). |
| `SALT_MASTER_PUBKEY_B64` | Base64-encoded master public key for direct trust without fingerprint. |
| `SALT_PKI_DIR` | Salt PKI directory; defaults to `/etc/salt/pki/minion`. The entrypoint sets `pki_dir` and places the minion and master keys there. |
| `SALT_MINION_PRIVATE_KEY_B64` | Base64-encoded minion private key (pre-seeded keypair). |
| `SALT_MINION_PUBLIC_KEY_B64` | Base64-encoded minion public key (pre-seeded keypair). |
| `SALT_LOG_LEVEL` | Sets minion log level. Default: `info`. |
| `SALT_AUTH_TIMEOUT` | Seconds to wait before master auth retry. Default: `60`. |
| `SALT_MASTER_ALIVE_INTERVAL` | Seconds between master connection checks. Default: `60`. |
| `SALT_RECON_DEFAULT` | ZeroMQ reconnect backoff start (ms). Default: `1000`. |
| `SALT_RECON_MAX` | ZeroMQ reconnect backoff max (ms). Default: `5000`. |
| `SALT_RECON_RANDOMIZE` | Jitter reconnect delay to prevent thundering herd. Default: `true`. |
| `SALT_FIPS_MODE` | Enable FIPS-compliant crypto. Default: `true`. |
| `VAULT_ADDR` | Vault server address (enables saltext.vault). |
| `VAULT_AUTH_METHOD` | Vault auth method: `approle` or `token`. Default: `approle`. |
| `VAULT_ROLE_ID` | Vault AppRole role ID. |
| `VAULT_SECRET_ID` | Vault AppRole secret ID. |
| `VAULT_SECRET_ID_FILE` | Path to Vault secret ID file. |
| `VAULT_TOKEN` | Vault authentication token. |
| `VAULT_TOKEN_FILE` | Path to Vault token file. |

Additional configuration can be mounted as read-only volumes:

```bash
docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --volume ./pillar:/srv/pillar:ro \
  --volume ./states:/srv/salt:ro \
  salt-minion:local
```

### Health check

The image health check verifies the minion can respond to local requests:

```bash
docker run --detach \
  --name salt-minion-test \
  --env SALT_MASTER=127.0.0.1 \
  salt-minion:local
```

Wait for health check:

```bash
sleep 40
```

Inspect health:

```bash
docker inspect salt-minion-test \
  --format 'Status={{.State.Status}} Health={{.State.Health.Status}}'
```

Expected:

```text
Status=running Health=healthy
```

Remove container:

```bash
docker rm --force salt-minion-test
```

### Smoke test

```bash
docker run --rm \
  salt-minion:local \
  salt-minion --version
```

```bash
docker run --rm \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c 'salt-call --local test.ping'
```

## VCF Minion

A specialized Salt Minion image for VMware Cloud Foundation (VCF) deployments. Includes:
- VMware `saltext.vcf` extension (vCenter, NSX, SDDC-M, VCF Ops automation)
- Vault integration for credentials sourcing
- Configurable extensions support
- Full project structure (Dockerfile, Docker Compose, Kubernetes Helm chart)

The VCF minion is a complete project directory with its own documentation and deployment options.

### Building VCF Minion

From the minion/vcf directory:

```bash
docker build \
  --platform linux/arm64 \
  --tag salt-minion-vcf:local \
  ./src/minion/vcf
```

### VCF-Specific Documentation

See the complete VCF minion documentation:

- **Helm Chart**: `helm/salt-minion-vcf/README.md` - Kubernetes deployment with StatefulSet
- **Full Project**: `../salt-minion-vcf/README.md` - Docker, Docker Compose, and advanced features

## Kubernetes and Helm

Both minion flavors include Helm charts for Kubernetes deployment.

### Kubernetes Minion Helm Chart

Located at: `helm/salt-minion`

Supports two deployment modes:
- **in_cluster** (default): Minion runs as Deployment inside cluster
- **external**: RBAC only for minion running outside cluster

Features:
- Declarative minion key management (via Salt Key Operator)
- CIS Kubernetes compliance assessment support
- Optional Vault integration
- PKI persistence across restarts
- Security hardening (non-root, no privilege escalation)

```bash
# Prepare
helm dependency update ./helm/salt-minion

# Lint
helm lint ./helm/salt-minion

# Validate
helm template salt-minion \
  ./helm/salt-minion \
  --set agent.saltMasterHost=salt-master.example.com \
  | kubectl apply --dry-run=client --validate=true -f -

# Install
helm upgrade --install salt-minion \
  ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.example.com
```

### VCF Minion Helm Chart

Located at: `helm/salt-minion-vcf` (in separate project directory)

Features:
- StatefulSet for stable identity
- Persistent PKI storage
- Vault integration
- Pillar Secret support
- Health checks (liveness and readiness probes)

```bash
helm upgrade --install salt-minion-vcf \
  ./helm/salt-minion-vcf \
  --namespace salt \
  --create-namespace \
  --set salt.master=salt-master.example.com \
  --set persistence.enabled=true
```

## Configuration

### Minion Identity

Minion ID can be set in multiple ways:

1. **Environment variable** (highest priority):
   ```bash
   SALT_MINION_ID=my-minion
   ```

2. **Pod hostname** (Kubernetes default):
   - For Deployment: random pod name
   - For StatefulSet: stable ordinal name (e.g., `salt-minion-vcf-0`)

3. **Explicit values in Helm**:
   ```yaml
   agent:
     minion:
       id: my-custom-id
   ```

### Key Management

Keys are stored at `/etc/salt/pki/minion/`:

- `minion.pem` - Private key (mode 0400)
- `minion.pub` - Public key (mode 0644)

#### Self-Generated Keys (Development)

```bash
docker run --rm \
  --env SALT_MASTER=localhost \
  --env SALT_MINION_PRIVATE_KEY_B64='' \  # Empty = self-generate
  salt-minion:local
```

#### Pre-Seeded Keys (Production)

```bash
# Encode existing keypair
PRIVATE_KEY=$(base64 -w0 < /path/to/minion.pem)
PUBLIC_KEY=$(base64 -w0 < /path/to/minion.pub)

docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --env SALT_MINION_PRIVATE_KEY_B64="$PRIVATE_KEY" \
  --env SALT_MINION_PUBLIC_KEY_B64="$PUBLIC_KEY" \
  salt-minion:local
```

### Multi-Master Setup

Connect to multiple masters simultaneously (Salt native multi-master mode):

```bash
docker run --rm \
  --env SALT_MASTER="master-0.example.com,master-1.example.com,master-2.example.com" \
  salt-minion:local
```

The comma-separated list becomes a YAML list in minion configuration.

### Vault Integration

Enable Vault for secure credential sourcing:

```bash
docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --env VAULT_ADDR=https://vault.example.com:8200 \
  --env VAULT_AUTH_METHOD=approle \
  --env VAULT_ROLE_ID=my-role-id \
  --env VAULT_SECRET_ID_FILE=/run/secrets/vault_secret_id \
  --volume /path/to/secret:/run/secrets/vault_secret_id:ro \
  salt-minion:local
```

Or in Helm:

```yaml
agent:
  vault:
    addr: https://vault.example.com:8200
    authMethod: approle
    roleId: my-role-id
    secretIdFile: /var/run/secrets/vault/secret_id
```

### FIPS Compliance

FIPS mode is enabled by default. Disable only if master isn't FIPS-enforced:

```bash
docker run --rm \
  --env SALT_MASTER=salt-master.example.com \
  --env SALT_FIPS_MODE=false \
  salt-minion:local
```

## Security Design

The images apply the following security controls:

- Salt Minion runs as non-root UID/GID `10000`
- No privilege escalation allowed
- All Linux capabilities dropped
- Private keys stored with mode `0400`
- Public keys stored with mode `0644`
- Corporate CA (if used) not retained in final image
- Kubernetes Secret sources remain read-only
- Automatic minion acceptance disabled by default
- Pre-seeded keys support declarative trust model

## Health Checks

### Docker Health Check

The image includes a Docker health check:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD salt-call --local test.ping >/dev/null 2>&1
```

### Kubernetes Health Probes

Helm charts include:

**Liveness Probe** - Verifies minion process is responsive
- Initial delay: 30s (kubernetes), 20s (VCF)
- Period: 60s (kubernetes), 30s (VCF)
- Timeout: 10s
- Failure threshold: 3

**Readiness Probe** - Verifies minion is ready for commands
- Initial delay: 15s (kubernetes), 10s (VCF)
- Period: 30s
- Timeout: 10s
- Failure threshold: 3

Both use: `salt-call --local test.ping`

## Validation Performed

The following validations were completed:

- Helm linting for both charts
- Kubernetes client-side validation of rendered templates
- ARM64 builds of both images
- Salt version verification
- Non-root UID/GID verification
- Directory ownership verification
- Build-time CA removal verification
- Docker health check validation
- In-cluster minion deployment and connectivity
- StatefulSet persistent identity verification
- Multi-master minion connectivity
- Key persistence across pod restarts
- Kubernetes API communication (saltext.kubernetes)
- Vault integration (saltext.vault)

## Related Documentation

- [Salt Minion Helm Chart](../../helm/salt-minion/README.md) - Kubernetes deployment details
- [VCF Minion Project](../../../salt-minion-vcf/) - Complete VCF minion documentation
- [Complete System Test Guide](../../docs/complete-system-test.md) - Integration testing procedures
- [Salt Project Documentation](https://docs.saltproject.io/) - Salt configuration and modules

## Troubleshooting

### Minion not connecting to master

Check master hostname resolution:

```bash
docker run --rm \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c 'nslookup salt-master.example.com'
```

Check network connectivity:

```bash
docker run --rm \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c 'nc -zv salt-master.example.com 4506'
```

View minion logs:

```bash
docker logs salt-minion-container-name
```

### Health check failing

Test manually:

```bash
docker exec salt-minion-container-name \
  salt-call --local test.ping
```

### FIPS mode issues

If master is not FIPS-enforced, disable FIPS:

```bash
--env SALT_FIPS_MODE=false
```

Default algorithms: `OAEP-SHA224` and `PKCS1v15-SHA224`

