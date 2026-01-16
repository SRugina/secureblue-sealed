#!/bin/sh
set -euo pipefail

# # Global Variables

# Provides `skopeo` (needed for `./digest.sh`) and `bootc` CLIs.
BOOTC_IMG="${BOOTC_IMG:-quay.io/fedora/fedora-bootc:43}"

UPSTREAM_IMG="${UPSTREAM_IMG:-ghcr.io/secureblue/silverblue-main-hardened:43}"
BASE_IMG="${BASE_IMG:-localhost/silverblue-main-hardened-bootc:43}"
SEALED_IMG="${SEALED_IMG:-localhost/silverblue-main-hardened-sealed:43}"

script_dir=$(cd $(dirname $0) && pwd)

# # Build Base Image
# Since upstream cannot be used as-is (yet, see README).

echo "Building base image..."
podman build -t $BASE_IMG \
	--build-arg upstream=$UPSTREAM_IMG \
	--network host \
	-f "$script_dir"/Containerfile.base .

# # Compute Digest

# Should be last 128 bytes of stdout from `./digest.sh`.
echo "Getting digest from ENV / Starting calculation..."
CFS_DIGEST="${CFS_DIGEST:-$(SKIP_DECOMPRESS=${SKIP_DECOMPRESS:-} "$script_dir"/digest.sh $BASE_IMG | tr -d '[:space:]' | tail -c 128)}"

echo "."
echo "."
echo "."
echo "$CFS_DIGEST" > "script_dir"/digest-for-reference.txt
echo "$CFS_DIGEST"
echo "."
echo "."
echo "."

# Sanity check.
if [ "${#CFS_DIGEST}" -ne 128 ]; then
	echo "ERROR: CFS_DIGEST length is ${#CFS_DIGEST}, expected 128."
	exit 1
fi

# # Build Sealed Image

echo "Building sealed image..."
podman build -t $SEALED_IMG \
	--build-arg COMPOSEFS_FSVERITY=${CFS_DIGEST} \
	--build-arg base=${BASE_IMG} \
	--build-arg buildroot=${BOOTC_IMG} \
	--network host \
	-f "$script_dir"/Containerfile.sealed .

