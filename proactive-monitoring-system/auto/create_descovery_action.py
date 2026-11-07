import json
import urllib.request

ZABBIX_URL = "http://127.0.0.1/zabbix/api_jsonrpc.php"
ADMIN_USER = "Admin"
ADMIN_PASS = "zabbix" # Default Zabbix admin password on fresh installs

def zabbix_api_call(method, params, auth=None):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "auth": auth,
        "id": 1
    }
    req = urllib.request.Request(
        ZABBIX_URL,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json-rpc'}
    )
    try:
        with urllib.request.urlopen(req) as response:
            res = json.loads(response.read().decode())
            return res.get("result")
    except Exception as e:
        print(f"API call failed for {method}: {e}")
        return None

def main():
    print("Waiting for Zabbix web frontend to become responsive...")
    import time
    for _ in range(30):
        try:
            with urllib.request.urlopen("http://127.0.0.1/zabbix/") as resp:
                if resp.status == 200:
                    break
        except Exception:
            time.sleep(2)

    # 1. Authenticate to get auth token
    auth_token = zabbix_api_call("user.login", {"username": ADMIN_USER, "password": ADMIN_PASS})
    if not auth_token:
        print("Failed to authenticate with Zabbix API.")
        return

    # 2. Get or create a Host Group (e.g., Linux servers)
    groups = zabbix_api_call("hostgroup.get", {"output": ["groupid"], "filter": {"name": ["Linux servers"]}}, auth_token)
    if groups:
        group_id = groups[0]["groupid"]
    else:
        new_group = zabbix_api_call("hostgroup.create", {"name": "Linux servers"}, auth_token)
        group_id = new_group["groupids"][0]

    # 3. Get Template ID for "Linux by Zabbix agent active"
    templates = zabbix_api_call("template.get", {"output": ["templateid"], "filter": {"host": ["Linux by Zabbix agent active"]}}, auth_token)
    template_id = templates[0]["templateid"] if templates else "10001" # Fallback ID

    # 4. Create the Auto-Registration Action
    action_params = {
        "name": "Linux Auto-Registration",
        "eventsource": 2, # Auto-registration events
        "status": 0,      # Enabled
        "conditions": [
            {
                "conditiontype": 24, # Host metadata
                "operator": 2,       # contains
                "value": "Linux"
            }
        ],
        "operations": [
            {"operationtype": 1}, # Add host
            {"operationtype": 4, "opgroup": [{"groupid": group_id}]}, # Add to host group
            {"operationtype": 6, "optemplate": [{"templateid": template_id}]} # Link template
        ]
    }
    
    result = zabbix_api_call("action.create", action_params, auth_token)
    if result and "actionids" in result:
        print(f"Successfully created Linux Auto-Registration Action ID: {result['actionids'][0]}")
    else:
        print("Action creation skipped or already exists.")

if __name__ == "__main__":
    main()