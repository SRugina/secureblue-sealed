#!/bin/sh

SEALED_IMG="${SEALED_IMG:-localhost/silverblue-main-hardened-sealed:43}"

if [ "${SKIP_COPY_TO_ROOTFUL:-}" = "1" ]; then
	echo "INFO: SKIP_COPY_TO_ROOTFUL=1 detected, so skipping." >&2
else
	echo "Copying SEALED_IMG to rootful podman..."
  # `--uncompressed` needed due to bug with compressed layers per
  # https://github.com/bootc-dev/bootc/issues/1703#issuecomment-3562107282
	podman save --format=oci-archive --uncompressed "$SEALED_IMG" | run0 podman load
fi

echo "Executing bootc switch ..."
run0 bootc switch --transport containers-storage $SEALED_IMG

