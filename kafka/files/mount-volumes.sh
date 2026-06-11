#!/usr/bin/env bash

set -euo pipefail

#############################
# INPUTS
#############################

MOUNT_BASE="${1:?Mount base required}"
USER_NAME="${2:?User required}"
GROUP_NAME="${3:?Group required}"

FS_TYPE="xfs"
COUNT=1

#############################
# ROOT DEVICE DETECTION (Amazon Linux safe)
#############################

ROOT_SOURCE=$(findmnt -no SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)

echo "Root disk: $ROOT_DISK"

#############################
# GET ALL NON-ROOT DISKS
#############################

ALL_DISKS=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}')

DEVICE_LIST=""

for d in $ALL_DISKS; do
    if [[ "$d" != "$ROOT_DISK" ]]; then
        DEVICE_LIST+="$d "
    fi
done

echo "Disks detected: $DEVICE_LIST"

#############################
# PROCESS EACH DISK
#############################

for DEV in $DEVICE_LIST; do

    DEVICE="/dev/$DEV"
    MOUNT_POINT="${MOUNT_BASE}/${COUNT}"

    echo "Processing $DEVICE → $MOUNT_POINT"

    #############################
    # FORMAT IF NO FS EXISTS
    #############################

    FSTYPE=$(lsblk -dn -o FSTYPE "$DEVICE" | tr -d '[:space:]')

    if [[ -z "$FSTYPE" ]]; then
        echo "Formatting $DEVICE as XFS"
        mkfs.xfs -f "$DEVICE"
        sleep 2
    fi

    #############################
    # CREATE MOUNT POINT
    #############################

    mkdir -p "$MOUNT_POINT"

    #############################
    # SAFE MOUNT (IDEMPOTENT)
    #############################

    if ! mountpoint -q "$MOUNT_POINT"; then
        echo "Mounting $DEVICE on $MOUNT_POINT"
        mount "$DEVICE" "$MOUNT_POINT"
    else
        echo "$MOUNT_POINT already mounted"
    fi

    #############################
    # OWNERSHIP
    #############################

    chown "$USER_NAME:$GROUP_NAME" "$MOUNT_POINT"

    #############################
    # FSTAB (SAFE USING UUID)
    #############################

    UUID=$(blkid -s UUID -o value "$DEVICE" || true)

    if [[ -n "$UUID" ]]; then
        if ! grep -q "$UUID" /etc/fstab; then
            echo "UUID=$UUID  $MOUNT_POINT  xfs  defaults,nofail  0  2" >> /etc/fstab
        fi
    fi

    #############################
    # GROW FILESYSTEM IF NEEDED
    #############################

    if mountpoint -q "$MOUNT_POINT"; then
        xfs_growfs "$MOUNT_POINT" || true
    fi

    COUNT=$((COUNT + 1))

done

echo "All volumes mounted successfully"