# helios-ai-api — the HELIOS multi-LLM hub as REST (src/ai/HELIOS.AIHub.Api).
#
# Deliberately no `# syntax=docker/dockerfile:1` directive: it makes BuildKit
# fetch its frontend image from docker.io before anything else, which is this
# build's only Docker Hub dependency (both FROM images are MCR) and has caused
# transient registry timeouts in CI. The builtin frontend covers every feature
# used here.
#
# Build from the REPO ROOT (the build needs src/ai, the src/core seam files,
# config/*.json, and nuget.config from the context):
#
#   docker build -f docker/helios-ai-api.Dockerfile -t helios-ai-api .
#
# Restore is deterministic without secrets: nuget.config's packageSourceMapping
# sends everything to nuget.org and only HELIOS.* package ids (none referenced
# here) would touch the private GitHub source.

# ---------------------------------------------------------------------------
# Build stage: restore + publish the API, and opportunistically cmake-build the
# optional native spoke. HELIOS.AIHub.csproj copies the .so into the output
# only when it exists (Condition="Exists(...)"), and the hub has managed
# fallbacks, so every native step is best-effort (|| true) by design.
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

# Optional native toolchain in one layer; a mirror hiccup or missing package
# must never fail the image build — the native spoke is optional.
RUN (apt-get update \
      && apt-get install -y --no-install-recommends cmake g++ make \
      && rm -rf /var/lib/apt/lists/*) || true

WORKDIR /source

# Project graph first, so `dotnet restore` caches as its own layer.
# HELIOS.AIHub.Api -> HELIOS.AIHub -> HELIOS.AIHub.Domain (F#); the source-linked
# core seam files are compile-time only and arrive with the full source copy below.
COPY nuget.config ./
COPY src/ai/HELIOS.AIHub.Domain/HELIOS.AIHub.Domain.fsproj src/ai/HELIOS.AIHub.Domain/
COPY src/ai/HELIOS.AIHub/HELIOS.AIHub.csproj src/ai/HELIOS.AIHub/
COPY src/ai/HELIOS.AIHub.Api/HELIOS.AIHub.Api.csproj src/ai/HELIOS.AIHub.Api/
RUN dotnet restore src/ai/HELIOS.AIHub.Api/HELIOS.AIHub.Api.csproj

# Full sources: the three projects, the native spoke, and the two source-linked
# seam files (../../core/HELIOS.Platform/Core/AI/... from HELIOS.AIHub.csproj).
COPY src/core/HELIOS.Platform/Core/AI/ src/core/HELIOS.Platform/Core/AI/
COPY src/ai/HELIOS.AIHub.Domain/ src/ai/HELIOS.AIHub.Domain/
COPY src/ai/HELIOS.AIHub/ src/ai/HELIOS.AIHub/
COPY src/ai/HELIOS.AIHub.Api/ src/ai/HELIOS.AIHub.Api/
COPY src/ai/HELIOS.AIHub.Native/ src/ai/HELIOS.AIHub.Native/

# Native spoke build into the exact path HELIOS.AIHub.csproj probes
# (src/ai/HELIOS.AIHub.Native/build/libhelios_aihub_native.so). Skips cleanly
# when the toolchain layer above didn't materialize.
RUN (cmake -S src/ai/HELIOS.AIHub.Native -B src/ai/HELIOS.AIHub.Native/build \
        -DCMAKE_BUILD_TYPE=Release \
      && cmake --build src/ai/HELIOS.AIHub.Native/build --config Release) \
    || echo "native spoke skipped — managed fallbacks will be used"

RUN dotnet publish src/ai/HELIOS.AIHub.Api/HELIOS.AIHub.Api.csproj \
      -c Release --no-restore -o /app/publish

# ---------------------------------------------------------------------------
# Runtime stage: aspnet + python3 (PythonInsightsSpoke shells to `python3` with
# the spoke directory as CWD; without it /v1/insights degrades to null) and
# curl for the HEALTHCHECK. ca-certificates ships with the base image.
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/publish/ /app/

# Python spoke (dependency-free by default). HELIOS_PYTHON_SPOKE below points
# PythonInsightsSpoke straight at it — no directory walk needed in-container.
COPY src/ai/python/ /opt/helios/python/

# Config: aihub.json plus its siblings (model-catalog.json is resolved as a
# sibling of whichever config AIHUB_CONFIG selects). Env-var names only — no
# secrets are baked into the image.
COPY config/*.json /app/config/

# Learning state (learning.localPath: .helios/learning/outcomes.jsonl, relative
# to WORKDIR): pre-create it owned by the non-root `app` user (built into the
# .NET 8 images) so a named volume mounted at /app/.helios inherits ownership.
RUN mkdir -p /app/.helios/learning && chown -R app:app /app/.helios

ENV ASPNETCORE_URLS=http://0.0.0.0:5170 \
    AIHUB_CONFIG=/app/config/aihub.json \
    HELIOS_PYTHON_SPOKE=/opt/helios/python

EXPOSE 5170

USER app

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:5170/healthz || exit 1

# AssemblyName is helios-ai-api, so the framework-dependent entry dll is fixed.
ENTRYPOINT ["dotnet", "helios-ai-api.dll"]
