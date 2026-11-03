#!/usr/bin/env bash
# Usage: scripts/helm-validation/test-webhook-excluded-labels.sh [chart-dir]
# Set BASELINE_REF=<git ref> to also check the default render is unchanged vs that ref.
# Renders the controller webhook for every way of setting
# controller.webhook.excluded.podMatchExpressions and controller.webhook.excluded.namespaces and
# checks the objectSelector and namespaceSelector expressions, and that values.schema.json rejects
# invalid values.
set -u
CHART=${1:-.}
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
BASE=(--set-string agent.token=1 --set-string agent.image.tag=1)
P=controller.webhook.excluded.podMatchExpressions
N=controller.webhook.excluded.namespaces
DEF_APP="datafy-controller,datafy-agent,aws-cluster-autoscaler,aws-node,cilium-operator,cilium-node-init,ztunnel-cilium,eks-pod-identity-agent,eks-pod-identity-agent-hybrid,eks-pod-identity-agent-hybrid-bottlerocket,nvidia-device-plugin,kyverno-admission-controller,kyverno-background-controller,kyverno-cleanup-controller,kyverno-reports-controller"
DEF_K8S="kube-dns,kube-proxy,coredns,node-local-dns,aws-node,calico-node,calico-typha,canal,cilium,cilium-envoy,kube-router,kindnet,istio-cni-node,linkerd-cni"
DEF_APPL="flannel,antrea,multus,kube-ovn-cni,kube-ovn-controller,ovn-central,ztunnel,istiod,kuma-cni,kong-mesh-cni,consul,efs-csi-node,fsx-csi-node,s3-csi-node,secrets-store-csi-driver,secrets-store-csi-driver-provider-aws"
KEYS0="app.kubernetes.io/name,k8s-app,app,datafy.io/webhook"
MP=s3.csi.aws.com/mountpoint-version
pass=0; fail=0

render() { helm template t "$CHART" "${BASE[@]}" -s templates/controller-webhook.yaml "$@"; }

# Mutation webhook objectSelector only: values of every expression with label key $1, in order
list() {
  awk -v want="$1" '
    /objectSelector:/ { inobj=1; next }
    inobj && /clientConfig:/ { exit }
    inobj && /- key:/ { k=$3; gsub(/"/, "", k); inlist=(k == want); next }
    inobj && inlist && /^ *- / { v=$2; gsub(/"/, "", v); out = out (out ? "," : "") v }
    END { print out }'
}
# Mutation webhook objectSelector only: operators of every expression with label key $1, in order
op_of() {
  awk -v want="$1" '
    /objectSelector:/ { inobj=1; next }
    inobj && /clientConfig:/ { exit }
    inobj && /- key:/ { k=$3; gsub(/"/, "", k); inlist=(k == want); next }
    inobj && inlist && /operator:/ { v=$2; gsub(/"/, "", v); out = out (out ? "," : "") v }
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

# Mutation webhook namespaceSelector only: values of the NotIn list for label key $1
ns_list() {
  awk -v want="\"$1\"" '
    /namespaceSelector:/ { inns=1; next }
    inns && /objectSelector:/ { exit }
    inns && /- key:/ { inlist=($3 == want); next }
    inns && inlist && /^ *- / { v=$2; gsub(/"/, "", v); out = out (out ? "," : "") v }
    END { print out }'
}

ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1"; shift; for l in "$@"; do echo "      $l"; done; fail=$((fail+1)); }

# check name "key=expected;OP:key=expected;KEYS=...;NS=...;NS_OPTOUT=..." helm-args...
check() {
  local name=$1 specs=$2; shift 2
  local out; if ! out=$(render "$@" 2>&1); then bad "$name" "render error: $out"; return; fi
  local spec key want got errs=()
  IFS=';' read -ra arr <<<"$specs"
  for spec in "${arr[@]}"; do
    key=${spec%%=*}; want=${spec#*=}
    if [[ $key == KEYS ]]; then got=$(keys_of <<<"$out"); elif [[ $key == NS ]]; then got=$(ns_list kubernetes.io/metadata.name <<<"$out");
    elif [[ $key == NS_OPTOUT ]]; then got=$(ns_list datafy.io/webhook <<<"$out");
    elif [[ $key == OP:* ]]; then got=$(op_of "${key#OP:}" <<<"$out"); else got=$(list "$key" <<<"$out"); fi
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

cat > "$S/e-all.yaml" <<'EOF'
controller:
  webhook:
    excluded:
      podMatchExpressions:
        - key: app.kubernetes.io/name
          values: [istio-cni, aws-node]
        - key: s3.csi.aws.com/mountpoint-version
          operator: DoesNotExist
        - key: component
          operator: NotIn
          values: [my-agent]
        - key: component
          values: [other-agent]
EOF
cat > "$S/e-app.yaml" <<'EOF'
controller:
  webhook:
    excluded:
      podMatchExpressions:
        - key: app
          values: [foo]
EOF
cat > "$S/e-empty.yaml" <<'EOF'
controller:
  webhook:
    excluded:
      podMatchExpressions: []
EOF
cat > "$S/e-null.yaml" <<'EOF'
controller:
  webhook:
    excluded:
      podMatchExpressions:
EOF
cat > "$S/e-blank-values.yaml" <<'EOF'
controller:
  webhook:
    excluded:
      podMatchExpressions:
        - key: app
          values: [""]
EOF
cat > "$S/e-no-webhook.yaml" <<'EOF'
controller:
  webhook: null
EOF

DEFAULTS="app.kubernetes.io/name=$DEF_APP;k8s-app=$DEF_K8S;app=$DEF_APPL;datafy.io/webhook=disabled;KEYS=$KEYS0"
NOTIN4="OP:app.kubernetes.io/name=NotIn;OP:k8s-app=NotIn;OP:app=NotIn;OP:datafy.io/webhook=NotIn"

check "defaults: built-ins only, all NotIn"  "$DEFAULTS;$NOTIN4"
check "operator defaults to NotIn"           "app=$DEF_APPL,foo;OP:app=NotIn,NotIn;KEYS=$KEYS0,app" \
                                             --set "$P[0].key=app" --set "$P[0].values={foo}"
check "explicit NotIn"                       "app=$DEF_APPL,foo;OP:app=NotIn,NotIn;KEYS=$KEYS0,app" \
                                             --set "$P[0].key=app" --set "$P[0].operator=NotIn" --set "$P[0].values={foo}"
check "DoesNotExist renders without values"  "OP:$MP=DoesNotExist;$MP=;KEYS=$KEYS0,$MP" \
                                             --set "$P[0].key=$MP" --set "$P[0].operator=DoesNotExist"
check "values file: entries appended in order, not merged" \
      "app.kubernetes.io/name=$DEF_APP,istio-cni,aws-node;OP:$MP=DoesNotExist;component=my-agent,other-agent;KEYS=$KEYS0,app.kubernetes.io/name,$MP,component,component" \
      -f "$S/e-all.yaml"
check "dotted key via --set needs no escaping" "app.kubernetes.io/name=$DEF_APP,my-app;KEYS=$KEYS0,app.kubernetes.io/name" \
                                             --set "$P[0].key=app.kubernetes.io/name" --set "$P[0].values={my-app}"
check "blank and repeated values dropped"    "app=$DEF_APPL,foo,bar" --set "$P[0].key=app" --set "$P[0].values={foo,foo,,bar}"
check "--set scalars quoted as strings"      "app=$DEF_APPL,true,1" --set "$P[0].key=app" --set "$P[0].values={true,1}"
check "--set-string values"                  "app=$DEF_APPL,123" --set "$P[0].key=app" --set-string "$P[0].values[0]=123"
check "--set by index edits the values-file list" \
      "app=$DEF_APPL,foo;app.kubernetes.io/name=$DEF_APP;component=my-agent,other-agent;KEYS=$KEYS0,app,$MP,component,component" \
      -f "$S/e-all.yaml" --set "$P[0].key=app" --set "$P[0].values={foo}"
check "later values file replaces the list"  "component=;app=$DEF_APPL,foo;KEYS=$KEYS0,app" -f "$S/e-all.yaml" -f "$S/e-app.yaml"
check "empty list in file"                   "$DEFAULTS" -f "$S/e-empty.yaml"
check "list set to null"                     "$DEFAULTS" -f "$S/e-all.yaml" --set "$P=null"
check "null list in file"                    "$DEFAULTS" -f "$S/e-null.yaml"
check "controller.webhook removed"           "$DEFAULTS" -f "$S/e-no-webhook.yaml"
check "Sensor mode with expressions"         "app=$DEF_APPL,foo" --set agent.mode=Sensor --set extendedInstallOnSensor=true \
                                             --set "$P[0].key=app" --set "$P[0].values={foo}"
check "pod opt-out label extended by a second expression" "datafy.io/webhook=disabled,off;KEYS=$KEYS0,datafy.io/webhook" \
                                             --set "$P[0].key=datafy.io/webhook" --set "$P[0].values={off}"
check "namespaces: none excluded by default" "NS=;NS_OPTOUT=disabled"
check "namespaces via --set, deduped"        "NS=calico-system,istio-system;$DEFAULTS" --set "$N={calico-system,istio-system,calico-system}"
check "namespaces empty {}"                  "NS=" --set "$N={}"
check "namespaces blank item dropped"        "NS=calico-system" --set "$N={calico-system,}"
check "namespaces keep opt-out label"        "NS=calico-system;NS_OPTOUT=disabled" --set "$N={calico-system}"

expect_error "operator In rejected"          'must be one of the following: "NotIn", "DoesNotExist"' \
                                             --set "$P[0].key=app" --set "$P[0].operator=In" --set "$P[0].values={x}"
expect_error "operator Exists rejected"      'must be one of the following: "NotIn", "DoesNotExist"' \
                                             --set "$P[0].key=app" --set "$P[0].operator=Exists"
expect_error "NotIn without values"          "podMatchExpressions.0: values is required" --set "$P[0].key=app"
expect_error "NotIn with only blank values"  'the NotIn expression on "app" needs at least one non-empty value' -f "$S/e-blank-values.yaml"
expect_error "DoesNotExist with values"      "podMatchExpressions.0.values: Array must have at most 0 items" \
                                             --set "$P[0].key=$MP" --set "$P[0].operator=DoesNotExist" --set "$P[0].values={x}"
expect_error "missing key"                   "podMatchExpressions.0: key is required" --set "$P[0].values={x}"
expect_error "unknown field in an entry"     "Additional property value is not allowed" \
                                             --set "$P[0].key=app" --set "$P[0].values={x}" --set "$P[0].value=x"
expect_error "map instead of list"           "podMatchExpressions: Invalid type" --set "$P.app={x}"
expect_error "old podLabels key"             "Additional property podLabels is not allowed" \
                                             --set "controller.webhook.excluded.podLabels.app={x}"
expect_error "namespaces plain string"       "excluded.namespaces: Invalid type" --set "$N=calico-system"

# entries name yaml: writes a values file whose podMatchExpressions list items are the given
# YAML lines (indented as list items) and prints its path
entries() {
  printf 'controller:\n  webhook:\n    excluded:\n      podMatchExpressions:\n%s\n' "$2" > "$S/bad-$1.yaml"
  echo "$S/bad-$1.yaml"
}
X63=$(printf 'a%.0s' {1..63}); X64=${X63}a

# Bad podMatchExpressions: list and entry shape
expect_error "list is a plain string"        "podMatchExpressions: Invalid type. Expected: [array,null], given: string" --set "$P=app"
expect_error "entry is a string"             "podMatchExpressions.0: Invalid type. Expected: object, given: string" --set "$P={app}"
expect_error "entry is null"                 "podMatchExpressions.0: Invalid type. Expected: object, given: null" \
                                             -f "$(entries entry-null '        - null')"
expect_error "second entry bad, first valid" "podMatchExpressions.1: key is required" \
                                             --set "$P[0].key=app" --set "$P[0].values={x}" --set "$P[1].values={y}"
expect_error "matchLabels-style entry"       "Additional property app is not allowed" \
                                             -f "$(entries match-labels '        - app: ztunnel')"
# Bad key
expect_error "empty key"                     "podMatchExpressions.0.key: Does not match pattern" \
                                             -f "$(entries empty-key '        - key: ""
          values: [x]')"
expect_error "key is a number"               "podMatchExpressions.0.key: Invalid type. Expected: string, given: integer" \
                                             --set "$P[0].key=123" --set "$P[0].values={x}"
expect_error "key with spaces"               "podMatchExpressions.0.key: Does not match pattern" --set "$P[0].key=bad key" --set "$P[0].values={x}"
expect_error "key with empty name"           "podMatchExpressions.0.key: Does not match pattern" --set "$P[0].key=example.com/" --set "$P[0].values={x}"
expect_error "key with uppercase prefix"     "podMatchExpressions.0.key: Does not match pattern" --set "$P[0].key=Example.com/app" --set "$P[0].values={x}"
expect_error "key with two slashes"          "podMatchExpressions.0.key: Does not match pattern" --set "$P[0].key=a/b/c" --set "$P[0].values={x}"
expect_error "key name over 63 characters"   "podMatchExpressions.0.key: Does not match pattern" --set "$P[0].key=$X64" --set "$P[0].values={x}"
# Bad operator
expect_error "operator lowercase"            'operator must be one of the following: "NotIn", "DoesNotExist"' \
                                             --set "$P[0].key=app" --set "$P[0].operator=notin" --set "$P[0].values={x}"
expect_error "operator empty string"         'operator must be one of the following: "NotIn", "DoesNotExist"' \
                                             --set "$P[0].key=app" --set "$P[0].operator=" --set "$P[0].values={x}"
expect_error "operator In from values file"  'operator must be one of the following: "NotIn", "DoesNotExist"' \
                                             -f "$(entries op-in '        - key: app
          operator: In
          values: [ztunnel]')"
# Bad values
expect_error "values is a plain string"      "podMatchExpressions.0.values: Invalid type" --set "$P[0].key=app" --set "$P[0].values=foo"
expect_error "values is a map"               "podMatchExpressions.0.values: Invalid type" --set "$P[0].key=app" --set "$P[0].values.a=b"
expect_error "NotIn values null"             "podMatchExpressions.0.values: Invalid type. Expected: array, given: null" \
                                             --set "$P[0].key=app" --set "$P[0].values=null"
expect_error "NotIn values empty list"       "podMatchExpressions.0.values: Array must have at least 1 items" \
                                             -f "$(entries values-empty '        - key: app
          values: []')"
expect_error "value is an object"            "podMatchExpressions.0.values.0: Invalid type" \
                                             -f "$(entries value-object '        - key: app
          values: [{a: b}]')"
expect_error "value is a list"               "podMatchExpressions.0.values.0: Invalid type" \
                                             -f "$(entries value-list '        - key: app
          values: [[a]]')"
expect_error "value with spaces"             "podMatchExpressions.0.values.0: Does not match pattern" \
                                             --set "$P[0].key=app" --set "$P[0].values={bad value}"
expect_error "value with leading dash"       "podMatchExpressions.0.values.0: Does not match pattern" \
                                             --set "$P[0].key=app" --set "$P[0].values={-foo}"
expect_error "value over 63 characters"      "podMatchExpressions.0.values.0: String length must be less than or equal to 63" \
                                             --set "$P[0].key=app" --set "$P[0].values={$X64}"
expect_error "bad value after a good one"    "podMatchExpressions.0.values.1: Does not match pattern" \
                                             --set "$P[0].key=app" --set "$P[0].values={ok,not ok}"
# Bad namespaces
expect_error "namespace with uppercase and _" "namespaces.0: Does not match pattern" --set "$N={Calico_System}"
expect_error "namespace over 63 characters"  "namespaces.0: String length must be less than or equal to 63" --set "$N={$X64}"

# Boundaries that must be accepted
check "DoesNotExist with empty values list"  "OP:$MP=DoesNotExist;$MP=" \
                                             -f "$(entries dne-empty '        - key: s3.csi.aws.com/mountpoint-version
          operator: DoesNotExist
          values: []')"
check "prefixed key and value charset"       "example.com/app_x.y-z=A.b_c-1" \
                                             --set "$P[0].key=example.com/app_x.y-z" --set "$P[0].values={A.b_c-1}"
check "63-character key name and value"      "$X63=$X63" --set "$P[0].key=$X63" --set "$P[0].values={$X63}"

if render --set agent.mode=Sensor --set extendedInstallOnSensor=false 2>/dev/null | grep -q MutatingWebhookConfiguration; then
  bad "Sensor + extendedInstallOnSensor=false renders no webhook"; else ok "Sensor + extendedInstallOnSensor=false renders no webhook"; fi

if render -f "$S/e-all.yaml" | sed -n '/agent-delete/,$p' | grep -qE 'istio-cni|mountpoint|my-agent'; then
  bad "agent-delete webhook untouched"; else ok "agent-delete webhook untouched"; fi

if render | sed -n '/objectSelector:/,/clientConfig:/p' | grep -q 'ebs-csi'; then
  bad "EBS CSI driver pods never excluded"; else ok "EBS CSI driver pods never excluded"; fi

# Default render must be byte-identical to the chart before this change
if [[ -n ${BASELINE_REF:-} ]]; then
  tmp=$(mktemp -d); git -C "$CHART" archive "$BASELINE_REF" | tar -x -C "$tmp"
  # installation-id is random per render; quoting is ignored since it does not change the parsed YAML
  if diff <(helm template t "$tmp" "${BASE[@]}" -s templates/controller-webhook.yaml | grep -v -E 'tls\.(crt|key)|caBundle|helm.sh/chart|installation-id' | tr -d '"') \
          <(render | grep -v -E 'tls\.(crt|key)|caBundle|helm.sh/chart|installation-id' | tr -d '"') >/dev/null; then
    ok "default render identical to $BASELINE_REF"; else bad "default render identical to $BASELINE_REF"; fi
  rm -rf "$tmp"
fi

if helm lint "$CHART" "${BASE[@]}" -f "$S/e-all.yaml" >/dev/null 2>&1; then ok "helm lint with values"; else bad "helm lint with values"; fi
if grep -n -E ' +$' "$CHART/values.yaml" "$CHART/templates/controller-webhook.yaml" "$CHART/templates/_webhook-excluded.tpl" "$CHART/values.schema.json" >/dev/null; then bad "no trailing spaces"; else ok "no trailing spaces"; fi

echo; echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
