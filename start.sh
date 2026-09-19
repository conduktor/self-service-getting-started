#!/bin/bash
set -euo pipefail

if [ -z "${CDK_LICENSE:-}" ]; then
  echo "CDK_LICENSE is not set. Self-service is a licensed feature and Console will"
  echo "reject every Self-service API call without it."
  echo "Export a license first:  export CDK_LICENSE=<your-license-key>"
  exit 1
fi

docker compose up --detach --wait
