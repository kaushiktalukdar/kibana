#!/usr/bin/env bash

set -euo pipefail

source .buildkite/scripts/common/util.sh
source .buildkite/scripts/steps/artifacts/env.sh

echo "--- Download and verify artifacts"
function download {
  buildkite-agent artifact download "$1" . --build "${KIBANA_BUILD_ID:-$BUILDKITE_BUILD_ID}"
  buildkite-agent artifact download "$1.sha512.txt" . --build "${KIBANA_BUILD_ID:-$BUILDKITE_BUILD_ID}"
  sha512sum -c "$1.sha512.txt"
  rm "$1.sha512.txt"
}

mkdir -p target
cd target

download "kibana-$FULL_VERSION-docker-image.tar.gz"
download "kibana-$FULL_VERSION-docker-image-aarch64.tar.gz"
download "kibana-ubi-$FULL_VERSION-docker-image.tar.gz"

download "kibana-$FULL_VERSION-arm64.deb"
download "kibana-$FULL_VERSION-amd64.deb"
download "kibana-$FULL_VERSION-x86_64.rpm"
download "kibana-$FULL_VERSION-aarch64.rpm"

download "kibana-$FULL_VERSION-docker-build-context.tar.gz"
download "kibana-ironbank-$FULL_VERSION-docker-build-context.tar.gz"
download "kibana-ubi-$FULL_VERSION-docker-build-context.tar.gz"

download "kibana-$FULL_VERSION-linux-aarch64.tar.gz"
download "kibana-$FULL_VERSION-linux-x86_64.tar.gz"

download "kibana-$FULL_VERSION-darwin-x86_64.tar.gz"
download "kibana-$FULL_VERSION-darwin-aarch64.tar.gz"

download "kibana-$FULL_VERSION-windows-x86_64.zip"

download "dependencies-$FULL_VERSION.csv"

cd -

echo "--- Set artifact permissions"
chmod -R a+r target/*
chmod -R a+w target

echo "--- Pull latest Release Manager CLI"
docker_with_retry pull docker.elastic.co/infra/release-manager:latest

echo "--- Publish artifacts"
if [[ "$BUILDKITE_BRANCH" == "$KIBANA_BASE_BRANCH" ]]; then
  export VAULT_ROLE_ID="$(get_vault_role_id)"
  export VAULT_SECRET_ID="$(get_vault_secret_id)"
  export VAULT_ADDR="https://secrets.elastic.co:8200"
  docker run --rm \
    --name release-manager \
    -e VAULT_ADDR \
    -e VAULT_ROLE_ID \
    -e VAULT_SECRET_ID \
    --mount type=bind,readonly=false,src="$PWD/target",target=/artifacts/target \
    docker.elastic.co/infra/release-manager:latest \
      cli collect \
        --project kibana \
        --branch "$KIBANA_BASE_BRANCH" \
        --commit "$GIT_COMMIT" \
        --workflow "$WORKFLOW" \
        --version "$BASE_VERSION" \
        --qualifier "$VERSION_QUALIFIER" \
        --artifact-set main

  ARTIFACTS_SUBDOMAIN="artifacts-$WORKFLOW"
  ARTIFACTS_SUMMARY=$(curl -s "https://$ARTIFACTS_SUBDOMAIN.elastic.co/kibana/latest/$FULL_VERSION.json" | jq -re '.summary_url')

  cat << EOF | buildkite-agent annotate --style "info" --context artifacts-summary
  ### Artifacts Summary

  $ARTIFACTS_SUMMARY
EOF

else
  echo "Skipping publish for untracked branch $BUILDKITE_BRANCH"
fi
