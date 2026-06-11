#!/usr/bin/env bash

set -euo pipefail

#############################
# CONFIG
#############################

AWS_REGION="us-east-1"

# Load environment variables
source /etc/environment

#############################
# VALIDATION
#############################

if [[ -z "${ebs_vols:-}" ]]; then
    echo "No ebs_vols defined. Exiting."
    exit 0
fi

if [[ -z "${ebs_count:-}" ]]; then
    echo "ebs_count not defined. Failing."
    exit 1
fi

echo "Starting EBS attachment process"
echo "Volume prefix: ${ebs_vols}"
echo "Volume count: ${ebs_count}"

#############################
# INSTANCE METADATA (IMDSv2 SAFE SIMPLE VERSION)
#############################

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)

AVAILABILITY_ZONE=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)

echo "Instance ID: $INSTANCE_ID"
echo "AZ: $AVAILABILITY_ZONE"

#############################
# FUNCTIONS
#############################

find_attached_volume() {
    local name="$1"

    aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --filters \
            "Name=status,Values=in-use" \
            "Name=tag:Name,Values=${name}" \
            "Name=availability-zone,Values=${AVAILABILITY_ZONE}" \
        --query "Volumes[0].Attachments[0].InstanceId" \
        --output text 2>/dev/null | grep -v None || true
}

find_available_volume() {
    local name="$1"

    aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --filters \
            "Name=status,Values=available" \
            "Name=tag:Name,Values=${name}" \
            "Name=availability-zone,Values=${AVAILABILITY_ZONE}" \
        --query "Volumes[0].VolumeId" \
        --output text 2>/dev/null | grep -v None || true
}

#############################
# MAIN LOOP
#############################

for i in $(seq 1 "$ebs_count"); do

    volume_name="${ebs_vols}${i}"

    echo "-----------------------------"
    echo "Processing volume: $volume_name"

    ATTACHED_INSTANCE=""
    VOLUME_ID=""

    #############################
    # Retry loop (handles detach delay)
    #############################
    for attempt in $(seq 1 20); do

        echo "Lookup attempt $attempt for $volume_name"

        ATTACHED_INSTANCE=$(find_attached_volume "$volume_name")
        VOLUME_ID=$(find_available_volume "$volume_name")

        # Already attached to this instance
        if [[ "$ATTACHED_INSTANCE" == "$INSTANCE_ID" ]]; then
            echo "Volume already attached to this instance"
            VOLUME_ID=""
            break
        fi

        # Volume exists and is available
        if [[ -n "$VOLUME_ID" && "$VOLUME_ID" != "None" ]]; then
            break
        fi

        echo "Volume not ready yet, retrying..."
        sleep 10
    done

    #############################
    # Skip if already attached
    #############################
    if [[ "$ATTACHED_INSTANCE" == "$INSTANCE_ID" ]]; then
        continue
    fi

    #############################
    # Fail if not found
    #############################
    if [[ -z "$VOLUME_ID" || "$VOLUME_ID" == "None" ]]; then
        echo "ERROR: Could not find volume for $volume_name"
        exit 1
    fi

    echo "Attaching volume $VOLUME_ID to instance $INSTANCE_ID"

    #############################
    # ATTACH VOLUME
    #############################
    aws ec2 attach-volume \
        --region "$AWS_REGION" \
        --volume-id "$VOLUME_ID" \
        --instance-id "$INSTANCE_ID" \
        --device "/dev/sd$(printf "\\x$(printf %x $((96 + i))))"

    echo "Attach request sent for $VOLUME_ID"

done

echo "All EBS volumes processed"