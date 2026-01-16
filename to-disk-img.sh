#!/bin/sh
set -euo pipefail

# # Global Variables

# Find the rootful container storage.
graphroot=$(run0 podman system info -f '{{.Store.GraphRoot}}')
echo "INFO: rootful podman graphroot is $graphroot"

SEALED_IMG="${SEALED_IMG:-localhost/silverblue-main-hardened-sealed:43}"

DISK_IMG="${DISK_IMG:-./bootable.img}"

script_dir=$(cd $(dirname $0) && pwd)

# # Install to a Disk Image

if [ ! -e "$DISK_IMG" ] ; then
	fallocate -l 20G "$DISK_IMG"
fi

if [ "${SKIP_COPY_TO_ROOTFUL:-}" = "1" ]; then
	echo "INFO: SKIP_COPY_TO_ROOTFUL=1 detected, so skipping." >&2
else
	echo "Copying SEALED_IMG to rootful podman..."
  # `--uncompressed` needed due to bug with compressed layers per
  # https://github.com/bootc-dev/bootc/issues/1703#issuecomment-3562107282
	podman save --format=oci-archive --uncompressed "$SEALED_IMG" | run0 podman load
fi

echo "Making disk image..."

# `policy.json` is needed since secureblue's `/etc/containers/policy.json`
# prevents opening images from local `container-storage`.
run0 podman run \
	--rm --privileged --pid=host --user root \
	--security-opt label=disable \
	-it \
	-v "$script_dir"/policy.json:/etc/containers/policy.json:ro \
	-v "$graphroot":/var/lib/containers/storage \
	-e RUST_LOG=debug \
	-v "$DISK_IMG":"/data/$(basename $DISK_IMG)" \
	"$SEALED_IMG" sh -c "bootc install to-disk \
		--composefs-backend \
		--via-loopback "/data/$(basename $DISK_IMG)" \
		--wipe --filesystem "btrfs" \
		--bootloader systemd"

