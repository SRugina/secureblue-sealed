#!/bin/sh
set -euo pipefail

# # Global Variables

# Provides `skopeo` and `bootc` CLIs.
BOOTC_IMG="${BOOTC_IMG:-quay.io/fedora/fedora-bootc:43}"
echo "Pulling bootc image..." >&2
podman pull $BOOTC_IMG

BASE_IMG="${BASE_IMG:-${1:-localhost/silverblue-main-hardened-bootc:43}}"

script_dir=$(cd $(dirname $0) && pwd)

# Find the container storage.
graphroot=$(podman system info -f '{{.Store.GraphRoot}}')
echo "INFO: podman graphroot is $graphroot" >&2

# # Decompress Layers
# 
# Needed due to bug with compressed layers per
# https://github.com/bootc-dev/bootc/issues/1703#issuecomment-3562107282
if [ "${SKIP_DECOMPRESS:-}" = "1" ]; then
	echo "INFO: SKIP_DECOMPRESS=1 detected, skipping decompression workaround." >&2
else
	echo "Decompressing layers, this can take a while..." >&2
	podman run \
		--rm --privileged --user root \
		--security-opt label=type:unconfined_t \
		-it \
		-v "$graphroot":/var/lib/containers/storage \
		"$BOOTC_IMG" sh -c "mkdir /tmp/uncompressed-image && \
			skopeo copy --dest-decompress containers-storage:$BASE_IMG dir:/tmp/uncompressed-image && \
			skopeo copy dir:/tmp/uncompressed-image containers-storage:$BASE_IMG"
fi

# # Compute & Output Digest
#
# Modified from
# https://github.com/bootc-dev/bootc/blob/e074a41720c7dc9c95ec6d1308ddf884cb91b240/hack/compute-composefs-digest
# because we can't use our base image since secureblue's `/etc/containers/policy.json`
# prevents opening images from local `container-storage`,
# so need to use `$BOOTC_IMG` instead
# as we don't want to edit the file when computing the digest.

echo "Computing digest, this can take a while..." >&2

# --pull=never because most use cases for this really should be operating on pre-pulled images.
podman run \
	--pull=never \
	--net=none \
	--rm --privileged --user root \
	--security-opt label=disable \
	-it \
	-v "$graphroot":/var/lib/containers/storage \
	--tmpfs /var \
	-e RUST_LOG=debug \
	"$BOOTC_IMG" bootc container compute-composefs-digest-from-storage $BASE_IMG

