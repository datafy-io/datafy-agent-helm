#!/usr/bin/env bash

set +e

if [ -z "${DATAFY_TOKEN_FILE}" ]; then
  echo "ERROR: DATAFY_TOKEN_FILE env var is required"
  exit 1
fi

echo "waiting for datafy token at ${DATAFY_TOKEN_FILE} ..."
until [ -s "${DATAFY_TOKEN_FILE}" ]; do
  sleep 2
done
echo "datafy token is present"
