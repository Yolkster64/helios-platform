#!/usr/bin/env python3
"""Bounded stdio handshake/tool discovery; never invokes a tool or an LLM."""

import argparse
import asyncio
import json
import os
from pathlib import Path
import shutil
import signal
import time
import xml.etree.ElementTree as ET


VERSIONS = {"2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"}
REQUIRED_TOOLS = {
    "helios_ai_status", "helios_task_routing_get",
    "helios_operator_profile_get", "helios_operator_context_sync",
    "helios_operator_next_steps_get",
}
MAX_MESSAGE = 1024 * 1024


class ProbeError(Exception):
    """Only fixed, secret-free diagnostics are exposed to callers."""


async def handshake(process):
    async def send(payload):
        process.stdin.write((json.dumps({"jsonrpc": "2.0", **payload}) + "\n").encode())
        await process.stdin.drain()

    async def request(identifier, method, params=None):
        await send({"id": identifier, "method": method, "params": params or {}})
        for _ in range(100):
            line = await process.stdout.readline()
            if not line:
                raise ProbeError("server closed stdout before completing the handshake")
            try:
                message = json.loads(line)
            except (ValueError, UnicodeError):
                raise ProbeError("server stdout contains invalid JSON-RPC") from None
            if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
                raise ProbeError("server stdout contains invalid JSON-RPC")
            if "method" in message:
                if "id" in message:
                    # No roots, sampling, elicitation, or other client capability offered.
                    if message["method"] == "ping":
                        await send({"id": message["id"], "result": {}})
                    else:
                        await send({"id": message["id"], "error": {
                            "code": -32601, "message": "Client method not supported"}})
                continue
            if message.get("id") != identifier:
                raise ProbeError("server response ID does not match the request")
            if "error" in message or not isinstance(message.get("result"), dict):
                raise ProbeError("server rejected the request or returned an invalid result")
            return message["result"]
        raise ProbeError("server exceeded the protocol message limit")

    initial = await request(1, "initialize", {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "helios-health", "version": "1.0.0"},
    })
    version = initial.get("protocolVersion")
    if version not in VERSIONS:
        raise ProbeError("server selected an unsupported MCP protocol version")
    capabilities = initial.get("capabilities")
    if not isinstance(capabilities, dict) or not isinstance(capabilities.get("tools"), dict):
        raise ProbeError("server did not advertise tool discovery")
    await send({"method": "notifications/initialized"})
    names, cursors, cursor = set(), set(), None
    for identifier in range(2, 22):
        page = await request(identifier, "tools/list", {"cursor": cursor} if cursor else {})
        entries = page.get("tools")
        if not isinstance(entries, list):
            raise ProbeError("server returned an invalid tool list")
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
                raise ProbeError("server returned an invalid tool definition")
            names.add(entry["name"])
        cursor = page.get("nextCursor")
        if cursor is None:
            break
        if not isinstance(cursor, str) or not cursor or cursor in cursors:
            raise ProbeError("server returned an invalid or repeated page cursor")
        cursors.add(cursor)
    else:
        raise ProbeError("tool discovery exceeded the page limit")
    if not REQUIRED_TOOLS <= names:
        raise ProbeError("server is missing required HELIOS status/operator tools")
    await request(22, "ping")
    return {"protocolVersion": version, "toolCount": len(names)}


async def probe(command, repo_root, timeout=30):
    start = time.monotonic()
    report = {"scope": "mcp-stdio-discovery", "ready": False,
              "providerCalls": 0, "toolCalls": 0, "liveProviderVerified": False}
    process = None
    try:
        environment = dict(os.environ, HELIOS_REPO_ROOT=str(repo_root),
                           DOTNET_NOLOGO="true", DOTNET_CLI_TELEMETRY_OPTOUT="true")
        # stderr is deliberately discarded: server exceptions can contain sensitive
        # configuration, and a full log pipe must never deadlock the handshake.
        process = await asyncio.create_subprocess_exec(
            *command, cwd=repo_root, env=environment,
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL, limit=MAX_MESSAGE,
            start_new_session=os.name != "nt")
        report.update(await asyncio.wait_for(handshake(process), timeout))
        report.update(ready=True, detail="initialize, tool discovery, and ping passed")
    except asyncio.TimeoutError:
        report["detail"] = "MCP handshake timed out"
    except ProbeError as error:
        report["detail"] = str(error)
    except (OSError, ValueError, RuntimeError):
        report["detail"] = "MCP process could not start or violated the transport limits"
    finally:
        if process is not None:
            process.stdin.close()
            try:
                await asyncio.wait_for(process.wait(), 1)
            except asyncio.TimeoutError:
                try:
                    process.terminate()
                    await asyncio.wait_for(process.wait(), 1)
                except asyncio.TimeoutError:
                    process.kill()
                    await process.wait()
                except ProcessLookupError:
                    pass
            # dotnet run can spawn the application; reap its group on Unix even
            # if the launcher exited first. Windows receives stdin EOF normally.
            if os.name != "nt":
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        report["elapsedMs"] = round((time.monotonic() - start) * 1000)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dotnet", default=shutil.which("dotnet"))
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("--timeout must be greater than zero and at most 60 seconds")
    root = args.repo_root.resolve()
    project = root / "src/mcp/HELIOS.Mcp"
    try:
        framework = ET.parse(project / "HELIOS.Mcp.csproj").findtext(".//TargetFramework")
        if not framework or not framework.replace(".", "").isalnum():
            raise ValueError("invalid framework")
        assembly = project / "bin" / "Release" / framework / "HELIOS.Mcp.dll"
    except (OSError, ValueError, ET.ParseError):
        assembly = None
    if not args.dotnet:
        report = {"scope": "mcp-stdio-discovery", "ready": False,
                  "detail": "dotnet is missing; install the .NET 10 SDK",
                  "providerCalls": 0, "toolCalls": 0, "liveProviderVerified": False}
    elif assembly is None or not assembly.is_file():
        report = {"scope": "mcp-stdio-discovery", "ready": False,
                  "detail": "MCP build missing; run dotnet build HELIOS.sln -c Release",
                  "providerCalls": 0, "toolCalls": 0, "liveProviderVerified": False}
    else:
        # Invoke the same built server directly, avoiding a launcher child so
        # bounded teardown reaps the actual server on Windows as well as Unix.
        command = [args.dotnet, str(assembly)]
        report = asyncio.run(probe(command, root, args.timeout))
    print(json.dumps(report))
    return 0 if report["ready"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
