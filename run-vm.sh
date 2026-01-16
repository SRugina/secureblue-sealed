#!/bin/bash
set -euo pipefail

# Ensure we have the UEFI variables template locally so we don't modify the system one
if [ ! -f "OVMF_VARS.fd" ]; then
    # Try to find the OVMF vars file
    VARS_TEMPLATE="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
    if [ ! -f "$VARS_TEMPLATE" ]; then
        echo "Could not find $VARS_TEMPLATE. Please install edk2-ovmf or similar."
        exit 1
    fi
    cp "$VARS_TEMPLATE" ./OVMF_VARS.fd
fi

# Find the OVMF code file
CODE_FILE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
if [ ! -f "$CODE_FILE" ]; then
    echo "Could not find $CODE_FILE. Please install edk2-ovmf or similar."
    exit 1
fi

echo "Starting QEMU..."
echo "Press Ctrl+A then X to exit QEMU if running in terminal mode."

qemu-system-x86_64 \
    -enable-kvm \
    -m 4G \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$CODE_FILE" \
    -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
    -drive file=./bootable.img,format=raw,if=virtio \
    -serial mon:stdio

