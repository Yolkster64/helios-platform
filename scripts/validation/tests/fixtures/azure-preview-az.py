#!/usr/bin/env python3
"""Inert Azure CLI for preview-contract tests; never imports an Azure SDK."""

import json
import os
from pathlib import Path
import sys


args = sys.argv[1:]
with Path(os.environ["PREVIEW_TEST_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(args) + "\n")

scenario = os.environ.get("PREVIEW_TEST_SCENARIO", "ok")
subscription = os.environ["AZURE_SUBSCRIPTION_ID"]
tenant = os.environ["AZURE_TENANT_ID"]
resource_group = os.environ["AZURE_RESOURCE_GROUP"]
other_id = "99999999-9999-9999-9999-999999999999"

if args[:2] == ["account", "show"]:
    if scenario == "unauthenticated":
        sys.exit(19)
    query = args[args.index("--query") + 1]
    values = {
        "id": other_id if scenario == "wrong-subscription" else subscription,
        "tenantId": other_id if scenario == "wrong-tenant" else tenant,
        "state": "Disabled" if scenario == "disabled-account" else "Enabled",
    }
    print(values[query])
elif args[:2] == ["group", "show"]:
    if scenario == "missing-group":
        sys.exit(20)
    group_id = f"/subscriptions/{subscription}/resourceGroups/{resource_group}"
    print(group_id + "-other" if scenario == "wrong-group" else group_id)
elif args[:3] == ["deployment", "group", "validate"]:
    if scenario == "validation-failed":
        sys.exit(21)
elif args[:3] == ["deployment", "group", "what-if"]:
    if scenario == "what-if-failed":
        sys.exit(22)
    print('{"status":"Succeeded","changes":[]}')
else:
    print("Unexpected Azure command in preview contract", file=sys.stderr)
    sys.exit(99)
