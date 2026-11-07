#!/usr/bin/env python3
"""Create the Zabbix 7.0 auto-registration action "Linux Auto-Registration".
Run on the monitor VM after the Zabbix web page works:
    ZBX_PASS='your-admin-password' python3 setup_autoregistration.py
"""
import json
import os
import sys
import urllib.request

ZABBIX_URL = os.environ.get("ZBX_URL", "http://127.0.0.1/zabbix") + "/api_jsonrpc.php"
ADMIN_USER = os.environ.get("ZBX_USER", "Admin")
ADMIN_PASS = os.environ.get("ZBX_PASS", "zabbix")   # default on a fresh install

ACTION_NAME = "Linux Auto-Registration"
METADATA = "linux-server"                  # must be contained in the agent's HostMetadata
GROUP_NAME = "Linux servers"
TEMPLATE_NAMES = ["Linux by Zabbix agent active"]   # you can add "ICMP Ping" and "nagios checks" to monitor ping and Nagios checks
# TEMPLATE_NAMES = ["Linux by Zabbix agent active", "ICMP Ping", "nagios checks"]

def api(method, params, token=None):
    headers = {"Content-Type": "application/json-rpc"}
    if token:
        headers["Authorization"] = f"Bearer {token}"      # 7.0 way (body "auth" is deprecated)
    body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode()
    with urllib.request.urlopen(urllib.request.Request(ZABBIX_URL, data=body, headers=headers)) as r:
        data = json.loads(r.read().decode())
    if "error" in data:                                    # never hide API errors
        err = data["error"]
        sys.exit(f"API error in {method}: {err.get('message')} {err.get('data')}")
    return data["result"]


def main():
    token = api("user.login", {"username": ADMIN_USER, "password": ADMIN_PASS})
    print("Logged in.")

    # already there? then nothing to do
    if api("action.get", {"filter": {"name": [ACTION_NAME]}, "output": ["actionid"]}, token):
        print(f"Action '{ACTION_NAME}' already exists - nothing to do.")
        return

    # 1. host group (get or create)
    groups = api("hostgroup.get", {"filter": {"name": [GROUP_NAME]}, "output": ["groupid"]}, token)
    group_id = groups[0]["groupid"] if groups else api("hostgroup.create", {"name": GROUP_NAME}, token)["groupids"][0]

    # 2. templates (stop if one is missing instead of guessing an ID)
    templates = []
    for name in TEMPLATE_NAMES:
        found = api("template.get", {"filter": {"host": [name]}, "output": ["templateid"]}, token)
        if not found:
            sys.exit(f"Template '{name}' not found. Create it first or remove it from TEMPLATE_NAMES.")
        templates.append({"templateid": found[0]["templateid"]})

    # 3. the action
    result = api("action.create", {
        "name": ACTION_NAME,
        "eventsource": 2,                                   # 2 = auto-registration
        "status": 0,                                        # 0 = enabled
        "filter": {                                         # conditions live INSIDE "filter"
            "evaltype": 0,
            "conditions": [{"conditiontype": 24, "operator": 2, "value": METADATA}],  # host metadata contains
        },
        "operations": [
            {"operationtype": 2},                                              # 2 = add host
            {"operationtype": 4, "opgroup": [{"groupid": group_id}]},          # 4 = add to host group
            {"operationtype": 6, "optemplate": templates},                     # 6 = link templates
        ],
    }, token)
    print(f"Created action '{ACTION_NAME}' (ID {result['actionids'][0]}).")


if __name__ == "__main__":
    main()