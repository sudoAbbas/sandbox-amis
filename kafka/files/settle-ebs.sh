#!/usr/bin/env bash

set -euo pipefail

#############################
# CONFIG
#############################

CONFIG_FILE="/etc/sysconfig/ebs"
TIMEOUT=300
SLEEP_INTERVAL=10

#############################
# LOAD EXPECTED VOLUME COUNT
#############################

if [[ -f "$CONFIG_FILE" ]]; then
    # Expected format: ebs_count=3
    EXPECTED_EBS_VOLUME_COUNT=$(grep '^ebs_count=' "$CONFIG_FILE" | cut -d= -f2 || true)
else
    echo "Config file $CONFIG_FILE not found. Exiting."
    exit 0
fi

if [[ -z "${EXPECTED_EBS_VOLUME_COUNT:-}" ]]; then
    echo "No ebs_count defined. Nothing to wait for."
    exit 0
fi

echo "Waiting for $EXPECTED_EBS_VOLUME_COUNT EBS volume(s) to attach..."

#############################
# IDENTIFY ROOT DISK (Amazon Linux safe)
#############################

ROOT_SOURCE=$(findmnt -no SOURCE /)

# root source example:
# /dev/nvme0n1p1 OR /dev/xvda1

ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)

echo "Root disk detected as: $ROOT_DISK"

#############################
# WAIT LOOP
#############################

counter=0

while [[ $counter -lt $TIMEOUT ]]; do

    sleep "$SLEEP_INTERVAL"
    counter=$((counter + SLEEP_INTERVAL))

    #############################
    # GET ALL BLOCK DEVICES
    #############################

    # list disks only (not partitions)
    ALL_DISKS=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}')

    #############################
    # REMOVE ROOT DISK
    #############################

    EBS_DISKS=""

    for disk in $ALL_DISKS; do
        if [[ "$disk" != "$ROOT_DISK" ]]; then
            EBS_DISKS+="$disk "
        fi
    done

    CURRENT_COUNT=$(echo "$EBS_DISKS" | awk 'NF{print NF; exit} || {print 0}')

    echo "Detected EBS disks: $EBS_DISKS (count=$CURRENT_COUNT)"

    #############################
    # CHECK CONDITION
    #############################

    if [[ "$CURRENT_COUNT" -ge "$EXPECTED_EBS_VOLUME_COUNT" ]]; then
        echo "SUCCESS: Found required EBS volumes ($CURRENT_COUNT)"
        exit 0
    fi

    echo "Waiting... ($counter/$TIMEOUT seconds elapsed)"

done

#############################
# TIMEOUT FAILURE
#############################

echo "ERROR: Timeout waiting for EBS volumes"
echo "Expected: $EXPECTED_EBS_VOLUME_COUNT, Found: $CURRENT_COUNT"
exit 1