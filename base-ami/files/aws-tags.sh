#!/bin/bash
set -euo pipefail

echo "[bootstrap] loading EC2 tags..."

INSTANCE_ID=$(ec2-metadata -i | cut -d ' ' -f2)
AZ=$(ec2-metadata -z | cut -d ' ' -f2)
REGION=${AZ::-1}

TAGS=$(aws ec2 describe-tags \
  --region "$REGION" \
  --filters "Name=resource-id,Values=$INSTANCE_ID" \
  --query 'Tags[*].[Key,Value]' \
  --output text)

PROFILE_FILE="/etc/profile.d/aws-tags.sh"
ENV_FILE="/etc/environment"

sudo rm -f "$PROFILE_FILE"
sudo touch "$PROFILE_FILE"

while read -r KEY VALUE; do
  SAFE_KEY=$(echo "$KEY" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  VAR="AWS_TAG_${SAFE_KEY}"

  echo "export ${VAR}=\"${VALUE}\"" | sudo tee -a "$PROFILE_FILE" > /dev/null
  echo "${VAR}=\"${VALUE}\"" | sudo tee -a "$ENV_FILE" > /dev/null

  export "${VAR}=${VALUE}"

  echo "[bootstrap] ${VAR}=${VALUE}"
done <<< "$TAGS"

echo "[bootstrap] done"