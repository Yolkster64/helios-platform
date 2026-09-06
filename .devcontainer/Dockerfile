FROM mcr.microsoft.com/devcontainers/dotnet:8.0

# Legacy local-compose image. The supported default remains image-based
# configuration in .devcontainer/devcontainer.json.
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
