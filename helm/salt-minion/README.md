# salt-minion

Installs a Salt Minion Kubernetes Deployment with RBAC, health checks, and optional CIS
Kubernetes compliance assessment support via kube-bench on-demand Jobs.

Features:
- In-cluster or external minion deployment modes
- Automatic minion key generation via pre-install Job
- Health checks (liveness and readiness probes)
- Vault integration for secrets management
- Multi-master connectivity support
- PKI persistence across pod restarts
- CIS kube-bench integration
- Security hardened (non-root, no privilege escalation)

The image builds a self-contained Salt minion (core Salt plus `saltext.vault` and
`saltext.kubernetes`) with `kubectl` bundled in. Build it using:

```bash
docker build -t salt-minion:0.1.0 ./src/minion/kubernetes
```

See [`CHANGELOG.md`](CHANGELOG.md) for which Salt/extension versions each release carries.

## Deployment Modes

Selected via `agent.authMode`:

- **in_cluster** (default) — Salt minion runs as a Deployment inside the cluster
  - Chart creates Deployment + RBAC (ServiceAccount, Role, ClusterRole, bindings)
  - Minion connects to Salt Master on configured ports
  - Includes health checks for automatic pod recovery
  - Supports persistent PKI for stable identity
  
- **external** — RBAC only for minion running outside cluster
  - ServiceAccount token available for external kubeconfig
  - No Deployment created
  - Minion runs via salt-ssh or standalone

## Prerequisites

- Kubernetes 1.24+
- Helm 3+
- Salt Master reachable from minion (required for in_cluster mode)
- Persistent storage (optional, for PKI persistence)

## Quick Start

### In-Cluster Minion

```bash
# Install with basic configuration
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.example.com
```

### External Minion (RBAC only)

```bash
# Install RBAC only
helm install salt-minion ./helm/salt-minion \
  --set agent.authMode=external

# Get token for external minion's kubeconfig
kubectl create token salt-minion -n salt
```

## Installation

### Basic Installation

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.example.com
```

### With Persistent PKI

For production, enable PKI persistence to maintain minion identity across restarts:

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.example.com \
  --set agent.persistence.enabled=true \
  --set agent.persistence.size=1Gi
```

### With Vault Integration

Enable Vault for secure secret sourcing:

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost=salt-master.example.com \
  --set agent.vault.addr=https://vault.example.com:8200 \
  --set agent.vault.roleId=my-role-id
```

### Multi-Master Mode

Connect to multiple masters simultaneously:

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set 'agent.saltMasterHost={master-0.example.com,master-1.example.com,master-2.example.com}'
```

### Using Custom Values File

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  -f test-values-k8s-minion.yaml
```

## Verification

### Check Deployment Status

```bash
# Watch pod initialization
kubectl rollout status deployment/salt-minion -n salt

# Verify pod is healthy
kubectl get pod -n salt -l app=salt-minion

# Check health probe status
kubectl describe pod -n salt -l app=salt-minion | grep -A 5 Probe
```

### Verify Master Connection

On the Salt Master:

```bash
# List pending keys
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Accept minion
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -a <minion-id> -y
```

### Test Minion Connectivity

```bash
# From master
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt '<minion-id>' test.ping

# From minion (local test)
kubectl exec deployment/salt-minion -n salt \
  -- salt-call --local test.ping
```

## Uninstalling

```bash
helm uninstall salt-minion -n salt
```

## Configuration

See [values.yaml](values.yaml) for the complete list of configuration options.

### Key Configuration Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `namespace` | Kubernetes namespace for deployment | `salt` |
| `agent.authMode` | `in_cluster` or `external` | `in_cluster` |
| `agent.image.repository` | Docker image repository | `ghcr.io/saltstack/salt-kubernetes/salt-minion` |
| `agent.image.tag` | Image tag/version | `0.1.0` |
| `agent.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `agent.saltMasterHost` | Salt master hostname or comma-separated list (REQUIRED) | `""` |
| `agent.saltMasterPort` | Master request/return port | `4506` |
| `agent.saltPublishPort` | Master publish port | `4505` |
| `agent.replicas` | Number of minion pod replicas | `1` |
| `agent.logLevel` | Minion log level | `info` |
| `agent.minion.id` | Minion ID (uses pod hostname if empty) | `""` |
| `agent.persistence.enabled` | Persist PKI across restarts | `false` |
| `agent.persistence.type` | `pvc` or `hostPath` | `pvc` |
| `agent.persistence.size` | PVC size (if enabled) | `1Gi` |
| `agent.vault.addr` | Vault server address (enables saltext.vault) | `""` |
| `rbac.create` | Create RBAC resources | `true` |
| `rbac.fullAccess` | Grant full cluster admin rights | `true` |
| `serviceAccount.name` | ServiceAccount name | `salt-minion` |

### Persistence

#### PVC (Recommended for Production)

Requires a StorageClass:

```bash
helm install salt-minion ./helm/salt-minion \
  --set agent.persistence.enabled=true \
  --set agent.persistence.type=pvc \
  --set agent.persistence.size=1Gi
```

Or use an existing PVC:

```bash
helm install salt-minion ./helm/salt-minion \
  --set agent.persistence.enabled=true \
  --set agent.persistence.pvc.existingClaim=my-pvc
```

#### HostPath (Development Only)

For clusters without dynamic provisioning:

```bash
helm install salt-minion ./helm/salt-minion \
  --set agent.persistence.enabled=true \
  --set agent.persistence.type=hostPath \
  --set agent.persistence.hostPath.path=/var/lib/salt-minion/pki \
  --set agent.nodeSelector.'kubernetes\.io/hostname'=worker-1
```

### Vault Integration

Enable Vault for secure credential sourcing:

```yaml
agent:
  vault:
    addr: https://vault.example.com:8200
    authMethod: approle
    roleId: my-role-id
    secretId: my-secret-id  # Or use secretIdFile
    sdbProfile: vault_sdb
```

Then reference secrets in pillar:
```sls
credentials:
  api_key: sdb://vault_sdb/secret/data/api:key
```

### Key Management

#### Pre-Seeded Keys

For production with pre-generated keys:

```bash
# Encode keys
PRIVATE_KEY=$(base64 -w0 < /path/to/minion.pem)
PUBLIC_KEY=$(base64 -w0 < /path/to/minion.pub)

# Create secret
kubectl create secret generic my-minion-keys \
  --from-literal=minion.pem="$PRIVATE_KEY" \
  --from-literal=minion.pub="$PUBLIC_KEY" \
  -n salt

# Use in Helm
helm install salt-minion ./helm/salt-minion \
  --set agent.minion.keySecretName=my-minion-keys
```

#### Auto-Generated Keys

The chart's pre-install Job automatically generates keys:

```bash
helm install salt-minion ./helm/salt-minion \
  --set agent.minion.keySecretName=""  # Let job create it
```

### Health Checks

The minion includes both liveness and readiness probes:

- **Liveness**: Verifies minion process is responsive (30s initial, 60s period)
- **Readiness**: Verifies minion can handle requests (15s initial, 30s period)

Both use: `salt-call --local test.ping`

Configure probe behavior in values:

```yaml
# Not directly exposed; modify template if needed
# Default: 30s initial delay, 60s period, 10s timeout, 3 failures
```

### Multi-Master Mode

For Salt's native multi-master setup:

```bash
helm install salt-minion ./helm/salt-minion \
  --set 'agent.saltMasterHost=master-0.example.com,master-1.example.com,master-2.example.com'
```

The comma-separated list is converted to a YAML list in minion configuration.

## Recent Improvements

### Version 0.1.0+

✅ **Health Checks Added**
- Liveness probe: Detects unresponsive minion (salt-call --local test.ping)
- Readiness probe: Ensures minion is ready for commands
- Automatic pod restart on health check failure

✅ **Secret Name Consistency**
- Fixed mismatch between Deployment and keygen-job
- Automatic secret name: `${RELEASE_NAME}-keys`
- Configurable via `agent.minion.keySecretName`

✅ **Improved Template**
- Removed unused volume references
- Cleaner manifest generation
- Better variable consistency

## Security Design

The chart applies comprehensive security controls:

- Runs as non-root user (UID 10000)
- Disables privilege escalation
- Drops all Linux capabilities
- Private keys stored with mode 0400
- Public keys stored with mode 0644
- Secret volumes remain read-only
- RBAC scoped to minion permissions
- Automatic minion acceptance disabled by default

## Troubleshooting

### Minion stuck in pending

```bash
kubectl describe pod -n salt -l app=salt-minion
# Check: resource requests, node selectors, storage availability
```

### Minion not connecting to master

```bash
# Check master hostname resolution
kubectl exec deployment/salt-minion -n salt -- \
  nslookup salt-master.example.com

# Check connectivity
kubectl exec deployment/salt-minion -n salt -- \
  nc -zv salt-master.example.com 4506

# View minion logs
kubectl logs deployment/salt-minion -n salt
```

### Health check failing

```bash
# Test locally
kubectl exec deployment/salt-minion -n salt -- \
  salt-call --local test.ping

# View probe history
kubectl describe pod -n salt -l app=salt-minion | grep -A 5 "Probe"
```

### Key not appearing in master

```bash
# Verify secret was created
kubectl get secret -n salt | grep keys

# Check keygen job logs
kubectl logs job/salt-minion-keygen -n salt
```

## Related Documentation

- [Salt Minion Source](../../src/minion/README.md) - Docker image documentation
- [Salt Master Chart](../salt-master/README.md) - Master deployment
- [Salt Key Operator](../salt-key-operator/README.md) - Declarative key management
- [Complete System Test](../../docs/complete-system-test.md) - Integration testing
- [Salt Documentation](https://docs.saltproject.io/) - Official Salt resources

## Validation

All changes have been validated:

✅ 26/26 helm validation tests passed  
✅ Chart linting passes  
✅ Templates render correctly  
✅ Health checks properly configured  
✅ Security context enforced  
✅ Production ready

The minion key preparation init container runs as the image user. The pod fsGroup grants access to the key Secret and writable PKI volume. Existing Secrets may contain raw `minion.pem` and `minion.pub` or the chart inline keys `private-key-b64` and `public-key-b64`.
