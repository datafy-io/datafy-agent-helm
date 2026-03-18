#!/usr/bin/env bash
# Makes Kind nodes look like EC2 for the datafy-agent shell (IMDS at 169.254.169.254).
# The agent runs via nsenter on the node network; it probes real IMDS — plain K8s env vars are not enough.
#
# Uses AWS amazon-ec2-metadata-mock + iptables DNAT inside each Kind node container.
# Ref: https://github.com/aws/amazon-ec2-metadata-mock
#
# Run on the CI runner (or your Mac with Docker) after `kind create cluster`, before helm install.
set -euo pipefail

AEMM_VERSION="${AEMM_VERSION:-v1.13.0}"
AEMM_URL="https://github.com/aws/amazon-ec2-metadata-mock/releases/download/${AEMM_VERSION}/ec2-metadata-mock-linux-amd64"
AEMM_PORT="${AEMM_PORT:-1338}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL -o "$tmpdir/ec2-metadata-mock" "$AEMM_URL"
chmod +x "$tmpdir/ec2-metadata-mock"

# Discover nodes by image — works for any cluster name (default "kind" → kind-control-plane;
# helm/kind-action often uses "chart-testing" → chart-testing-control-plane).
mapfile -t nodes < <(docker ps --format '{{.Names}}	{{.Image}}' | awk '/kindest\/node/ {print $1}' || true)
if [[ ${#nodes[@]} -eq 0 ]]; then
  echo "No running containers with image kindest/node. Is Kind running? (docker ps)" >&2
  docker ps --format 'table {{.Names}}\t{{.Image}}' >&2 || true
  exit 1
fi

for c in "${nodes[@]}"; do
  echo "==> Fake IMDS on container: $c"
  docker cp "$tmpdir/ec2-metadata-mock" "$c:/usr/local/bin/ec2-metadata-mock"

  docker exec "$c" bash -ec "
    set -e
    killall ec2-metadata-mock 2>/dev/null || true
    sleep 1
    nohup /usr/local/bin/ec2-metadata-mock -p ${AEMM_PORT} </dev/null >/var/log/aemm.log 2>&1 &
    sleep 2
    if ! curl -sS --max-time 2 \"http://127.0.0.1:${AEMM_PORT}/latest/meta-data/instance-id\" | grep -q .; then
      echo 'AEMM did not respond on port ${AEMM_PORT}, see /var/log/aemm.log' >&2
      tail -80 /var/log/aemm.log >&2 || true
      exit 1
    fi
    # Redirect IMDS to AEMM (agent uses link-local address)
    iptables -t nat -C OUTPUT -d 169.254.169.254 -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:${AEMM_PORT} 2>/dev/null || \
    iptables -t nat -A OUTPUT -d 169.254.169.254 -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:${AEMM_PORT}
    # IMDSv2 token endpoint uses same host
    echo -n 'IMDS probe: '
    curl -sS --max-time 3 http://169.254.169.254/latest/meta-data/instance-id && echo ' OK' || echo ' FAIL'
  "
done

echo "Fake EC2 IMDS ready on Kind node(s)."
