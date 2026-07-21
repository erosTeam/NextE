#!/usr/bin/env bash
set -euo pipefail

readonly upstream_commit='696dc63bd0b4803f96cc3d4f844322cef4910f8e'
readonly upstream_source="${1:-https://github.com/hgmzhn/manga-translator-ui.git}"
readonly image_tag="${2:-nexte/manga-translator-ui:v1.9.9-nexte2}"
readonly base_image="${3:-nexte/manga-translator-ui:v1.9.9}"
readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly patch_path="${repository_root}/sidecar/manga-translator-ui-v1.9.9/0001-fix-load-text-workflow.patch"
readonly dockerfile_path="${repository_root}/sidecar/manga-translator-ui-v1.9.9/Dockerfile"
readonly build_root="$(mktemp -d /tmp/nexte-manga-sidecar-build.XXXXXX)"
readonly checkout_path="${build_root}/upstream"

cleanup() {
  rm -rf "${build_root}"
}
trap cleanup EXIT

git clone --no-checkout "${upstream_source}" "${checkout_path}"
git -C "${checkout_path}" checkout --detach "${upstream_commit}"
test "$(git -C "${checkout_path}" rev-parse HEAD)" = "${upstream_commit}"
git -C "${checkout_path}" apply --unidiff-zero --check "${patch_path}"
git -C "${checkout_path}" apply --unidiff-zero "${patch_path}"
if ! docker image inspect "${base_image}" >/dev/null 2>&1; then
  docker build \
    --file "${checkout_path}/packaging/Dockerfile" \
    --tag "${base_image}" \
    "${checkout_path}"
fi
docker build \
  --build-arg "BASE_IMAGE=${base_image}" \
  --file "${dockerfile_path}" \
  --tag "${image_tag}" \
  "${checkout_path}"

echo "Built ${image_tag} from ${upstream_commit} with the NextE load-text compatibility route."
