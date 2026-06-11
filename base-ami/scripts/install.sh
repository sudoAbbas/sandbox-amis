#!/bin/bash
set -euo pipefail

echo "[packer] installing base OS dependencies..."

sudo yum update -y

# basic tools only
sudo yum install -y unzip

# AWS CLI (OK to keep here if all AMIs need AWS access)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install

# filesystem tools only
sudo yum install -y cloud-utils-growpart

sudo mkdir -p /opt/bootstrap

echo "[packer] base dependencies installed"