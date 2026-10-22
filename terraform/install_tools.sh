#!/bin/bash
set -Eeuo pipefail

# EC2 user data runs as root. For manual recovery, use sudo bash install_tools.sh.
if [[ $EUID -ne 0 ]]; then
  echo "Run this script as root: sudo bash $0" >&2
  exit 1
fi

exec > >(tee -a /var/log/install-tools.log) 2>&1
trap 'echo "Bootstrap failed at line $LINENO: $BASH_COMMAND" >&2' ERR
export DEBIAN_FRONTEND=noninteractive

# Repair the Jenkins repository BEFORE apt update, including on failed instances.
# Ubuntu's EC2 image includes wget and CA certificates.
install -d -m 0755 /usr/share/keyrings
wget --tries=3 --timeout=30 -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
chmod 0644 /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list

apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y \
  ca-certificates wget gnupg fontconfig openjdk-21-jre snapd

# Install Java before Jenkins so the package can start its service.
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y jenkins
systemctl enable --now jenkins

# Docker installation
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y docker.io

# User data's $USER is root; grant access to the Ubuntu login user instead.
usermod -aG docker ubuntu
usermod -aG docker jenkins

systemctl enable --now docker
systemctl restart jenkins

# Use a repository-specific Trivy key instead of the deprecated apt-key command.
wget --tries=3 --timeout=30 -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/trivy.gpg
chmod 0644 /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  > /etc/apt/sources.list.d/trivy.list
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y trivy

# Skip existing snaps when recovering a partially configured instance.
if ! snap list aws-cli >/dev/null 2>&1; then
  snap install aws-cli --classic
fi
if ! snap list helm >/dev/null 2>&1; then
  snap install helm --classic
fi

systemctl is-active --quiet jenkins
echo "Bootstrap completed successfully. Jenkins is running on port 8080."
