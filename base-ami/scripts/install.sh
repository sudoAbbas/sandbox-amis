#!/bin/bash
set -euo pipefail

echo "[packer] installing base dependencies..."

sudo yum update -y

#################################################
# REQUIRED FIX: install unzip FIRST
#################################################
sudo yum install -y unzip

#################################################
# AWS CLI v2
#################################################
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip

unzip awscliv2.zip

sudo ./aws/install

#################################################
# ec2-metadata tool
#################################################
sudo yum install -y cloud-utils-growpart

#################################################
# bootstrap directory
#################################################
sudo mkdir -p /opt/bootstrap

echo "[packer] base dependencies installed"