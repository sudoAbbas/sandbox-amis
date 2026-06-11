packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "region" {
  default = "us-east-1"
}

source "amazon-ebs" "base" {
  region        = var.region
  instance_type = "t3.micro"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ssh_username = "ec2-user"
  ami_name     = "base-ec2-ami-{{timestamp}}"
}

build {
  sources = ["source.amazon-ebs.base"]

  provisioner "shell" {
    script = "scripts/install.sh"
  }

  provisioner "file" {
    source      = "files/aws-tags.sh"
    destination = "/tmp/aws-tags.sh"
  }

  provisioner "file" {
    source      = "files/aws-tags-bootstrap.service"
    destination = "/tmp/aws-tags-bootstrap.service"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/aws-tags.sh /opt/bootstrap/aws-tags.sh",
      "sudo chmod +x /opt/bootstrap/aws-tags.sh",

      "sudo mv /tmp/aws-tags-bootstrap.service /etc/systemd/system/aws-tags-bootstrap.service",

      "sudo systemctl daemon-reload",
      "sudo systemctl enable aws-tags-bootstrap.service"
    ]
  }
}