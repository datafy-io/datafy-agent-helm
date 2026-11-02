#!/usr/bin/env bash
# Usage: scripts/helm-validation/test-webhook-excluded-labels.sh [chart-dir]
# Set BASELINE_REF=<git ref> to also check the default render is unchanged vs that ref.
# Renders the controller webhook for every way of setting
# controller.webhook.excludedPods.labels and checks the objectSelector NotIn lists.
set -u
CHART=${1:-.}
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
BASE=(--set-string agent.token=1 --set-string agent.image.tag=1)
P=controller.webhook.excludedPods.labels
DEF_APP="datafy-controller,datafy-agent,aws-cluster-autoscaler,aws-node"
DEF_K8S="kube-dns,kube-proxy,coredns,aws-node,istio-cni-node"
DEF_APPL="ztunnel"
KEYS0="app.kubernetes.io/name,k8s-app,app"
pass=0; fail=0

render() { helm template t "$CHART" "${BASE[@]}" -s templates/controller-webhook.yaml "$@"; }

# Mutation webhook objectSelector only: values of every NotIn list for label key $1, in order
list() {
  awk -v want="$1" '
    /objectSelector:/ { inobj=1; next }
    inobj && /clientConfig:/ { exit }
    inobj && /- key:/ { k=$3; gsub(/"/, "", k); inlist=(k == want); next }
    inobj && inlist && /^ *- / { v=$2; gsub(/"/, "", v); out = out (out ? "," : "") v }
    END { print out }'
}
# Mutation webhook objectSelector only: label keys in order
keys_of() {
  awk '
    /objectSelector:/ { inobj=1; next }
    inobj && /clientConfig:/ { exit }
    inobj && /- key:/ { k=$3; gsub(/"/, "", k); out = out (out ? "," : "") k }
    END { print out }'
}

ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1"; shift; for l in "$@"; do echo "      $l"; done; fail=$((fail+1)); }

# check name "key=expected;key=expected" helm-args...
check() {
  local name=$1 specs=$2; shift 2
  local out; if ! out=$(render "$@" 2>&1); then bad "$name" "render error: $out"; return; fi
  local spec key want got errs=()
  IFS=';' read -ra arr <<<"$specs"
  for spec in "${arr[@]}"; do
    key=${spec%%=*}; want=${spec#*=}
    if [[ $key == KEYS ]]; then got=$(keys_of <<<"$out"); else got=$(list "$key" <<<"$out"); fi
    [[ $got == "$want" ]] || errs+=("$key got: $got" "$key want: $want")
  done
  if ((${#errs[@]})); then bad "$name" "${errs[@]}"; else ok "$name"; fi
}

# expect_error name message-substring helm-args...
expect_error() {
  local name=$1 msg=$2; shift 2
  local out; if out=$(render "$@" 2>&1); then bad "$name" "expected render error"; return; fi
  if [[ $out == *"$msg"* ]]; then ok "$name (error as expected)"; else bad "$name" "unexpected error: $out"; fi
}

cat > "$S/l-all.yaml" <<'EOF'
controller:
  webhook:
    excludedPods:
      labels:
        app.kubernetes.io/name: [ztunnel, istio-cni]
        k8s-app: [istio-cni-node, calico-node]
        app: [ztunnel]
        component: [my-agent]
EOF
cat > "$S/l-null.yaml" <<'EOF'
controller:
  webhook:
    excludedPods:
      labels:
        app:
        k8s-app:
EOF
cat > "$S/l-labels-null.yaml" <<'EOF'
controller:
  webhook:
    excludedPods:
      labels:
EOF
cat > "$S/l-no-webhook.yaml" <<'EOF'
controller:
  webhook: null
EOF

DEFAULTS="app.kubernetes.io/name=$DEF_APP;k8s-app=$DEF_K8S;app=$DEF_APPL;KEYS=$KEYS0"

check "defaults: built-ins only, no extra keys" "$DEFAULTS"
check "app via --set"                    "app=$DEF_APPL;KEYS=$KEYS0;k8s-app=$DEF_K8S" --set "$P.app={ztunnel}"
check "k8s-app via --set extends built-in" "k8s-app=$DEF_K8S,cilium,calico-node;KEYS=$KEYS0" --set "$P.k8s-app={cilium,calico-node}"
check "app.kubernetes.io/name escaped --set" "app.kubernetes.io/name=$DEF_APP,ztunnel;KEYS=$KEYS0" --set "$P.app\.kubernetes\.io/name={ztunnel}"
check "custom key via --set"             "component=my-agent;KEYS=$KEYS0,component" --set "$P.component={my-agent}"
check "two-flag Istio combo"             "app=$DEF_APPL;k8s-app=$DEF_K8S;app.kubernetes.io/name=$DEF_APP" \
                                         --set "$P.app={ztunnel}" --set "$P.k8s-app={istio-cni-node}"
check "--set by index"                   "app=$DEF_APPL,foo" --set "$P.app[0]=ztunnel" --set "$P.app[1]=foo"
check "--set-string by index"            "app=$DEF_APPL,123" --set-string "$P.app[0]=123"
check "values file, all keys"            "app.kubernetes.io/name=$DEF_APP,ztunnel,istio-cni;k8s-app=$DEF_K8S,calico-node;app=$DEF_APPL;component=my-agent;KEYS=$KEYS0,component" \
                                         -f "$S/l-all.yaml"
check "extra keys sorted, stable order"  "KEYS=$KEYS0,a-key,b-key,z-key" \
                                         --set "$P.z-key={z}" --set "$P.a-key={a}" --set "$P.b-key={b}"
check "values file + --set overrides key" "app=$DEF_APPL,other;component=my-agent" -f "$S/l-all.yaml" --set "$P.app={other}"
check "empty {} -> no extra key"         "$DEFAULTS" --set "$P.app={}"
check "empty {} on built-in key"         "$DEFAULTS" --set "$P.k8s-app={}"
check "blank item dropped"               "app=$DEF_APPL,foo" --set "$P.app={foo,}"
check "null values in file"              "$DEFAULTS" -f "$S/l-null.yaml"
check "labels: null"                     "$DEFAULTS" -f "$S/l-labels-null.yaml"
check "controller.webhook removed"       "$DEFAULTS" -f "$S/l-no-webhook.yaml"
check "value already in defaults"        "app.kubernetes.io/name=$DEF_APP" --set "$P.app\.kubernetes\.io/name={aws-node}"
check "Sensor mode with labels"          "app=$DEF_APPL,foo" --set agent.mode=Sensor --set extendedInstallOnSensor=true --set "$P.app={foo}"
check "ztunnel in k8s-app and app.kubernetes.io/name" "app.kubernetes.io/name=$DEF_APP,ztunnel;k8s-app=$DEF_K8S,ztunnel;KEYS=$KEYS0" \
                                         --set "$P.k8s-app={ztunnel}" --set "$P.app\.kubernetes\.io/name={ztunnel}"
check "new key app=test and test in app.kubernetes.io/name" "app.kubernetes.io/name=$DEF_APP,test;app=$DEF_APPL,test;KEYS=$KEYS0" \
                                         --set "$P.app={test}" --set "$P.app\.kubernetes\.io/name={test}"
check "only custom key boris-test"       "app.kubernetes.io/name=$DEF_APP;k8s-app=$DEF_K8S;boris-test=boris;KEYS=$KEYS0,boris-test" \
                                         --set "$P.boris-test={boris}"
check "app extends built-in, no second expression" "app=$DEF_APPL,foo;KEYS=$KEYS0" --set "$P.app={foo}"
check "duplicate values collapsed"       "app=$DEF_APPL,foo;k8s-app=$DEF_K8S,cilium;zz=a;KEYS=$KEYS0,zz" \
                                         --set "$P.app={foo,foo,ztunnel}" --set "$P.k8s-app={cilium,coredns,cilium}" --set "$P.zz={a,a}"
expect_error "plain string instead of list" "must be a list" --set "$P.app=ztunnel"
expect_error "unescaped dotted key"         "must be a list" --set "$P.app.kubernetes.io/name={ztunnel}"

if render --set agent.mode=Sensor --set extendedInstallOnSensor=false 2>/dev/null | grep -q MutatingWebhookConfiguration; then
  bad "Sensor + extendedInstallOnSensor=false renders no webhook"; else ok "Sensor + extendedInstallOnSensor=false renders no webhook"; fi

if render -f "$S/l-all.yaml" | sed -n '/agent-delete/,$p' | grep -qE 'ztunnel|calico|my-agent'; then
  bad "agent-delete webhook untouched"; else ok "agent-delete webhook untouched"; fi

# Default render must be byte-identical to the chart before this change
if [[ -n ${BASELINE_REF:-} ]]; then
  tmp=$(mktemp -d); git -C "$CHART" archive "$BASELINE_REF" | tar -x -C "$tmp"
  # installation-id is random per render; quoting is ignored since it does not change the parsed YAML
  if diff <(helm template t "$tmp" "${BASE[@]}" -s templates/controller-webhook.yaml | grep -v -E 'tls\.(crt|key)|caBundle|helm.sh/chart|installation-id' | tr -d '"') \
          <(render | grep -v -E 'tls\.(crt|key)|caBundle|helm.sh/chart|installation-id' | tr -d '"') >/dev/null; then
    ok "default render identical to $BASELINE_REF"; else bad "default render identical to $BASELINE_REF"; fi
  rm -rf "$tmp"
fi

if helm lint "$CHART" "${BASE[@]}" -f "$S/l-all.yaml" >/dev/null 2>&1; then ok "helm lint with values"; else bad "helm lint with values"; fi
if grep -n -E ' +$' "$CHART/values.yaml" "$CHART/templates/controller-webhook.yaml" >/dev/null; then bad "no trailing spaces"; else ok "no trailing spaces"; fi

echo; echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
