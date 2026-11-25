#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
  pwd
)"
REPO_DIR="$(
  cd -- "${SCRIPT_DIR}/.." &&
  pwd
)"
MASTER_NAMESPACE="salt-master"
MINION_NAMESPACE="salt"

MASTER_RELEASE="salt-master"
MINION_RELEASE="salt-minion"

MINION_ID="integration-test-minion"
MINION_SECRET="integration-test-minion-keys"

BUILD_CA="/private/tmp/cloud-services-root-ca.crt"
KEY_DIRECTORY="/private/tmp/salt-minion-integration-keys"

PIP_INDEX_URL="https://packages.vcfd.broadcom.net/artifactory/api/pypi/pypi-virtual/simple"
PACKAGES_IP="10.191.86.43"

cd "${REPO_DIR}"

echo "===================================================="
echo "1. Select Rancher Desktop"
echo "===================================================="

kubectl config use-context rancher-desktop
docker context use rancher-desktop

kubectl get nodes
helm version --short
docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}'
uname -m

echo "===================================================="
echo "2. Remove existing SaltMinionKey resources"
echo "===================================================="

if kubectl get crd saltminionkeys.salt.saltstack.io >/dev/null 2>&1; then
  kubectl delete saltminionkeys \
    --all \
    --all-namespaces \
    --wait=true \
    --timeout=60s 2>/dev/null || true

  # Fallback for resources left behind after an earlier operator removal.
  kubectl get saltminionkeys \
    --all-namespaces \
    --no-headers \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name' \
    2>/dev/null |
  while read -r resource_namespace resource_name; do
    [ -n "${resource_name}" ] || continue

    kubectl patch saltminionkey "${resource_name}" \
      --namespace "${resource_namespace}" \
      --type=merge \
      --patch '{"metadata":{"finalizers":[]}}' || true
  done
fi

echo "===================================================="
echo "3. Remove existing Helm releases"
echo "===================================================="

helm uninstall "${MINION_RELEASE}" \
  --namespace "${MINION_NAMESPACE}" 2>/dev/null || true

helm uninstall "${MASTER_RELEASE}" \
  --namespace "${MASTER_NAMESPACE}" 2>/dev/null || true

echo "===================================================="
echo "4. Remove existing namespaces and CRD"
echo "===================================================="

kubectl delete namespace \
  "${MINION_NAMESPACE}" \
  "${MASTER_NAMESPACE}" \
  --ignore-not-found=true \
  --wait=true \
  --timeout=3m

kubectl delete crd \
  saltminionkeys.salt.saltstack.io \
  --ignore-not-found=true

echo "===================================================="
echo "5. Download the Salt Master chart dependency"
echo "===================================================="

helm dependency update ./helm/salt-master

echo "===================================================="
echo "6. Validate all Helm charts"
echo "===================================================="

helm lint ./helm/salt-key-operator
helm lint ./helm/salt-master
helm lint ./helm/salt-minion --set agent.minion.allowSelfGeneratedKey=true

git diff --check

echo "===================================================="
echo "7. Export the corporate CA certificate"
echo "===================================================="

security find-certificate \
  -a \
  -c "Cloud Services Root CA" \
  -p \
  "${HOME}/Library/Keychains/login.keychain-db" \
  /Library/Keychains/System.keychain \
  /System/Library/Keychains/SystemRootCertificates.keychain \
  > "${BUILD_CA}"

test -s "${BUILD_CA}"

openssl x509 \
  -in "${BUILD_CA}" \
  -noout \
  -subject \
  -issuer \
  -dates

echo "===================================================="
echo "8. Build Salt Key Operator"
echo "===================================================="

docker build \
  --platform linux/arm64 \
  --tag salt-key-operator:local \
  ./src/salt-key-operator

echo "===================================================="
echo "9. Build Salt Master"
echo "===================================================="

docker build \
  --platform linux/arm64 \
  --secret "id=build_ca,src=${BUILD_CA}" \
  --tag salt-master:local \
  ./src/master

echo "===================================================="
echo "10. Build Salt Minion"
echo "===================================================="

docker build \
  --platform linux/arm64 \
  --add-host "packages.vcfd.broadcom.net:${PACKAGES_IP}" \
  --secret "id=build_ca,src=${BUILD_CA}" \
  --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL}" \
  --tag salt-minion:local \
  ./src/minion/kubernetes

echo "===================================================="
echo "11. Verify all local images"
echo "===================================================="

docker image inspect salt-key-operator:local \
  --format 'Image={{.RepoTags}} Architecture={{.Architecture}} OS={{.Os}}'

docker image inspect salt-master:local \
  --format 'Image={{.RepoTags}} Architecture={{.Architecture}} OS={{.Os}}'

docker image inspect salt-minion:local \
  --format 'Image={{.RepoTags}} Architecture={{.Architecture}} OS={{.Os}}'

docker run --rm \
  --platform linux/arm64 \
  salt-master:local \
  salt-master --version

docker run --rm \
  --platform linux/arm64 \
  --entrypoint /bin/sh \
  salt-minion:local \
  -c '
    set -eu
    id
    salt-minion --version
    kubectl version --client
    test ! -e /usr/local/share/ca-certificates/build-ca.crt
    echo "Build CA not persisted: PASS"
  '

echo "===================================================="
echo "12. Install Salt Master and Salt Key Operator"
echo "===================================================="

helm upgrade --install "${MASTER_RELEASE}" \
  ./helm/salt-master \
  --namespace "${MASTER_NAMESPACE}" \
  --create-namespace \
  --set namespace="${MASTER_NAMESPACE}" \
  --set agent.image.repository=salt-master \
  --set agent.image.tag=local \
  --set agent.image.pullPolicy=Never \
  --set agent.trustedMinions.enabled=true \
  --set salt-key-operator.image.repository=salt-key-operator \
  --set salt-key-operator.image.tag=local \
  --set salt-key-operator.image.pullPolicy=Never \
  --set salt-key-operator.watchNamespace="${MASTER_NAMESPACE}" \
  --wait \
  --wait-for-jobs \
  --timeout 5m

kubectl rollout status deployment/salt-key-operator \
  --namespace "${MASTER_NAMESPACE}" \
  --timeout=3m

kubectl rollout status deployment/salt-master \
  --namespace "${MASTER_NAMESPACE}" \
  --timeout=3m

kubectl get pods,jobs,secrets,configmaps,services \
  --namespace "${MASTER_NAMESPACE}"

kubectl get crd saltminionkeys.salt.saltstack.io

echo "===================================================="
echo "13. Generate the real Minion key pair"
echo "===================================================="

rm -rf "${KEY_DIRECTORY}"
mkdir -p "${KEY_DIRECTORY}"
chmod 0700 "${KEY_DIRECTORY}"

umask 077

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out "${KEY_DIRECTORY}/minion.pem"

openssl rsa \
  -pubout \
  -in "${KEY_DIRECTORY}/minion.pem" \
  -out "${KEY_DIRECTORY}/minion.pub"

chmod 0600 "${KEY_DIRECTORY}/minion.pem"
chmod 0644 "${KEY_DIRECTORY}/minion.pub"

echo "===================================================="
echo "14. Create the Minion namespace and Secret"
echo "===================================================="

kubectl create namespace "${MINION_NAMESPACE}"

kubectl create secret generic "${MINION_SECRET}" \
  --namespace "${MINION_NAMESPACE}" \
  --from-file=minion.pem="${KEY_DIRECTORY}/minion.pem" \
  --from-file=minion.pub="${KEY_DIRECTORY}/minion.pub"

kubectl get secret "${MINION_SECRET}" \
  --namespace "${MINION_NAMESPACE}"

echo "===================================================="
echo "15. Register the Minion public key"
echo "===================================================="

{
  printf '%s\n' \
    'apiVersion: salt.saltstack.io/v1alpha1' \
    'kind: SaltMinionKey' \
    'metadata:' \
    "  name: ${MINION_ID}" \
    "  namespace: ${MASTER_NAMESPACE}" \
    'spec:' \
    "  minionId: ${MINION_ID}" \
    '  publicKey: |'

  sed 's/^/    /' "${KEY_DIRECTORY}/minion.pub"
} | kubectl apply -f -

kubectl wait \
  --for=condition=Accepted \
  "saltminionkey/${MINION_ID}" \
  --namespace "${MASTER_NAMESPACE}" \
  --timeout=60s

kubectl get saltminionkey "${MINION_ID}" \
  --namespace "${MASTER_NAMESPACE}" \
  -o wide

echo "===================================================="
echo "16. Wait for key propagation into Salt Master"
echo "===================================================="

EXPECTED_MINION_KEY_HASH="$(
  shasum -a 256 "${KEY_DIRECTORY}/minion.pub" |
  awk '{print $1}'
)"

KEY_FOUND=false

for attempt in $(seq 1 24); do
  ACTUAL_MINION_KEY_HASH="$(
    kubectl exec deployment/salt-master \
      --namespace "${MASTER_NAMESPACE}" \
      --container salt-master \
      -- sha256sum \
      "/etc/salt/pki/master/minions/${MINION_ID}" \
      2>/dev/null |
    awk '{print $1}' || true
  )"

  if [ "${ACTUAL_MINION_KEY_HASH}" = "${EXPECTED_MINION_KEY_HASH}" ]; then
    KEY_FOUND=true
    echo "Trusted key propagation: PASS"
    break
  fi

  echo "Waiting for key propagation: ${attempt}/24"
  sleep 5
done

if [ "${KEY_FOUND}" != "true" ]; then
  echo "Trusted key propagation: FAIL"
  exit 1
fi

kubectl exec deployment/salt-master \
  --namespace "${MASTER_NAMESPACE}" \
  --container salt-master \
  -- salt-key -L

echo "===================================================="
echo "17. Render and validate the Salt Minion chart"
echo "===================================================="

MASTER_PUBLIC_KEY_B64="$(
  kubectl get secret salt-master-master-keys \
    --namespace "${MASTER_NAMESPACE}" \
    -o jsonpath='{.data.master\.pub}'
)"

helm template "${MINION_RELEASE}" \
  ./helm/salt-minion \
  --namespace "${MINION_NAMESPACE}" \
  --set namespace="${MINION_NAMESPACE}" \
  --set agent.image.repository=salt-minion \
  --set agent.image.tag=local \
  --set agent.image.pullPolicy=Never \
  --set agent.minion.id="${MINION_ID}" \
  --set agent.minion.keySecretName="${MINION_SECRET}" \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set-string agent.minion.masterPubKeyB64="${MASTER_PUBLIC_KEY_B64}" \
  --set rbac.fullAccess=false \
  > /tmp/salt-minion-rendered.yaml

kubectl apply \
  --dry-run=client \
  --validate=true \
  -f /tmp/salt-minion-rendered.yaml

echo "===================================================="
echo "18. Install the real Salt Minion"
echo "===================================================="

helm upgrade --install "${MINION_RELEASE}" \
  ./helm/salt-minion \
  --namespace "${MINION_NAMESPACE}" \
  --set namespace="${MINION_NAMESPACE}" \
  --set agent.image.repository=salt-minion \
  --set agent.image.tag=local \
  --set agent.image.pullPolicy=Never \
  --set agent.minion.id="${MINION_ID}" \
  --set agent.minion.keySecretName="${MINION_SECRET}" \
  --set agent.saltMasterHost=salt-master.salt-master.svc.cluster.local \
  --set-string agent.minion.masterPubKeyB64="${MASTER_PUBLIC_KEY_B64}" \
  --set rbac.fullAccess=false \
  --wait \
  --timeout 5m

kubectl rollout status deployment/salt-minion \
  --namespace "${MINION_NAMESPACE}" \
  --timeout=3m

echo "===================================================="
echo "19. Check all running workloads"
echo "===================================================="

kubectl get pods \
  --namespace "${MASTER_NAMESPACE}"

kubectl get pods \
  --namespace "${MINION_NAMESPACE}"

kubectl logs deployment/salt-minion \
  --namespace "${MINION_NAMESPACE}" \
  --container salt-minion \
  --tail=40

echo "===================================================="
echo "20. Run the real Master-to-Minion test"
echo "===================================================="

PING_OUTPUT="$(
  kubectl exec deployment/salt-master \
    --namespace "${MASTER_NAMESPACE}" \
    --container salt-master \
    -- salt \
    -t 30 \
    "${MINION_ID}" \
    test.ping
)"

echo "${PING_OUTPUT}"

echo "${PING_OUTPUT}" | grep -q "True"
echo "Master-to-Minion test.ping: PASS"

echo "===================================================="
echo "21. Restart the Minion and verify identity"
echo "===================================================="

kubectl rollout restart deployment/salt-minion \
  --namespace "${MINION_NAMESPACE}"

kubectl rollout status deployment/salt-minion \
  --namespace "${MINION_NAMESPACE}" \
  --timeout=3m

RESTARTED_MINION_KEY_HASH="$(
  kubectl exec deployment/salt-minion \
    --namespace "${MINION_NAMESPACE}" \
    --container salt-minion \
    -- sha256sum /etc/salt/pki/minion/minion.pub |
  awk '{print $1}'
)"

echo "Expected key hash:  ${EXPECTED_MINION_KEY_HASH}"
echo "Restarted key hash: ${RESTARTED_MINION_KEY_HASH}"

test "${EXPECTED_MINION_KEY_HASH}" = "${RESTARTED_MINION_KEY_HASH}"
echo "Minion identity after restart: PASS"

kubectl exec deployment/salt-master \
  --namespace "${MASTER_NAMESPACE}" \
  --container salt-master \
  -- salt \
  -t 30 \
  "${MINION_ID}" \
  test.ping

echo "===================================================="
echo "22. Verify restricted Minion RBAC"
echo "===================================================="

SERVICE_ACCOUNT="system:serviceaccount:${MINION_NAMESPACE}:salt-minion"

NODES_ACCESS="$(
  kubectl auth can-i list nodes \
    --as="${SERVICE_ACCOUNT}" 2>/dev/null || true
)"

SECRETS_ACCESS="$(
  kubectl auth can-i get secrets \
    --namespace "${MINION_NAMESPACE}" \
    --as="${SERVICE_ACCOUNT}" 2>/dev/null || true
)"

FULL_ACCESS="$(
  kubectl auth can-i '*' '*' \
    --as="${SERVICE_ACCOUNT}" 2>/dev/null || true
)"

echo "Can list nodes: ${NODES_ACCESS}"
echo "Can read Secrets: ${SECRETS_ACCESS}"
echo "Has unrestricted access: ${FULL_ACCESS}"

test "${NODES_ACCESS}" = "yes"
test "${SECRETS_ACCESS}" = "no"
test "${FULL_ACCESS}" = "no"

echo "Restricted RBAC validation: PASS"

echo "===================================================="
echo "23. Final status"
echo "===================================================="

helm status "${MASTER_RELEASE}" \
  --namespace "${MASTER_NAMESPACE}"

helm status "${MINION_RELEASE}" \
  --namespace "${MINION_NAMESPACE}"

echo
echo "===================================================="
echo "ALL SALT END-TO-END TESTS PASSED"
echo "===================================================="
