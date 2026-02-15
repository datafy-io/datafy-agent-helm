#!/usr/bin/env bash

set +e

if [ -z "${NODE_NAME}" ]; then
  echo "ERROR: NODE_NAME env var is required"
  exit 1
fi

/datafy/preflight-check.sh "${NODE_NAME}"
preflight_rc=$?

echo

if [ "$preflight_rc" -ne 0 ]; then
  echo "preflight failed (code=$preflight_rc)"
else
  echo "preflight succeeded (code=$preflight_rc)"
fi

exit "$preflight_rc"
