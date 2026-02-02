
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Avoid warnings by switching to non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install essential tools
# sshpass: for password scaling (if keys aren't used)
# openssh-client: for ssh
# iputils-ping, dnsutils: for networking debugging
RUN apt-get update && apt-get install -y \
    sshpass \
    openssh-client \
    git \
    vim \
    curl \
    wget \
    python3 \
    python3-pip \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Switch back to dialog for any ad-hoc use of apt-get
ENV DEBIAN_FRONTEND=dialog
