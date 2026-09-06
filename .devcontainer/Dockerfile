ARG VARIANT=8.0
FROM mcr.microsoft.com/devcontainers/dotnet:${VARIANT}

LABEL maintainer="HELIOS Development Team"
LABEL description="HELIOS development container base image"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    jq \
    less \
    libsqlite3-dev \
    postgresql-client \
    procps \
    shellcheck \
    sqlite3 \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*
