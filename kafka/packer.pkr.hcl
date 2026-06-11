packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "git_sha" {
  type    = string
  default = "local"
}

source "amazon-ebs" "kafka" {
  region = var.aws_region

  instance_type = "t3.large"

  ssh_username = "ec2-user"

  ami_name = "kafka-${formatdate("YYYYMMDD-hhmm", timestamp())}-${var.git_sha}"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      architecture        = "x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }

    owners      = ["137112412989"]
    most_recent = true
  }

  tags = {
    Name = "kafka"
    OS   = "amazon-linux-2023"
  }
}

build {
  sources = ["source.amazon-ebs.kafka"]

  provisioner "file" {
    source      = "files"
    destination = "/tmp/files"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"

    scripts = [
      "scripts/init-kafka.sh"
    ]
  }
}