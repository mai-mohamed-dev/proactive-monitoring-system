# Zabbix 7.0: Proactive Monitoring System

A small monitoring stack that runs on Vagrant VMs. One **monitor server** runs Zabbix 7.0. Any number of **target VMs** run an **active** Zabbix agent and add themselves to the server automatically (auto-registration). No Docker, no manual host creation.

## Architecture
- **Active agents** connect out to the server on **10051**. The server never polls them, so the targets need no inbound port.
- On first contact the agent sends its **hostname** and **HostMetadata** tag. An **autoregistration action** matches the tag, creates the host, and links the template.

## Requirements

- VirtualBox and Vagrant
- Vagrant plugin: `vagrant plugin install vagrant-hostmanager`
- All VMs on the same private network 
- Monitor server: Ubuntu 22.04 (`ubuntu/jammy64`), 2 GB RAM or more
- Targets: RHEL family 9 (CentOS Stream / Rocky / Alma) or Ubuntu/Debian


`monitor_provision.sh` installs MariaDB, the Zabbix 7.0 server, frontend and Apache, imports the schema, writes the frontend config (no setup wizard), installs an agent on the server itself, and creates the auto-registration action.

## Files

| File | Where it runs | Purpose |
|---|---|---|
| `monitor_provision.sh` | monitor VM (Vagrant provisioner) | Full server install + auto-registration action |
| `create_register_action.py` | monitor VM | Creates only the auto-registration action (Python, API) |
| `create_discovery_action.py` | monitor VM | Creates only the discovery action (Python, API) |
| `deploy_agents.sh` | RHEL-family target | Installs the 7.0 active agent and configures it |

## Settings that must match

| Setting | Server side | Agent side |
|---|---|---|
| Tag | Action condition: *Host metadata contains* `linux-server` | `HostMetadata=linux-server` |
| Name | The host created in Zabbix | `Hostname=` is the VM's short hostname and must be **unique** |
| Server address | Port **10051** reachable | `ServerActive=192.168.56.10` |

The tag match is **case-sensitive**: `Linux` does not match `linux-server`.

`127.0.0.1` for `Server`/`ServerActive` is correct only on the monitor VM, where server and agent share a machine. Every other VM must use `192.168.56.10`.

## Verify

- **Data collection > Hosts**: the target is listed with the template linked.
- **Monitoring > Latest data**: filter by the host. CPU, memory and other values should appear and update.
- **Alerts > Actions > Autoregistration actions**: `Linux Auto-Registration` is listed and enabled.
- On a target: `sudo tail -n 10 /var/log/zabbix/zabbix_agentd.log` shows no connection errors to `192.168.56.10:10051`.

## Alerts when a VM goes down

Problems appear under **Monitoring > Problems** (not under the Alerts menu).

- The active template waits a long time (30 minutes by default) before it raises "agent is not available". To shorten it, set the macro `{$AGENT.NODATA_TIMEOUT}` to `3m` on the template `Linux by Zabbix agent active`.
- For faster detection, link the `ICMP Ping` template. The server runs `fping`, which must work for the `zabbix` user, and the host's interface IP must be the `192.168.56.x` address, not the Vagrant NAT address `10.0.2.15`.
- To get emails or chat messages you also need a media type, media on your user, and an enabled trigger action.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Host never appears | Agent can't reach the server, or the tag doesn't match | check the agent log; confirm `HostMetadata` and the action condition are identical | Log: `system.sw.packages.get ... Unsupported item key` | Old 6.0 agent installed from EPEL | Remove it and reinstall from the 7.0 repo (`zabbix_agent_remove.sh`, then `zabbix_agent_install.sh`); the install script blocks EPEL's Zabbix packages |
| `zabbix-server` takes very long to start | systemd can't find the PID file | `PidFile` in `zabbix_server.conf` must match the unit file (`/run/zabbix/zabbix_server.pid`); `/run/zabbix` must belong to `zabbix`; start only through `systemctl` |
| Server fails with `cannot open config file ... Permission denied` | Wrong owner or mode on the config | `chown root:zabbix` and `chmod 640` on `/etc/zabbix/zabbix_server.conf` |
| Action script prints an API error | Wrong Admin password or web setup not finished | Re-run with `ZBX_PASS='your-password'` |
| Host shows no data but is listed | Wrong template, or a name mismatch | Check the host's **Templates** tab and the agent log |

## Security notes

- Change the default `Admin / zabbix` login and the `DB_PASS` in `monitor_provision.sh` before using this beyond a lab.
- The web UI is served over plain HTTP. Put it behind HTTPS for anything real.
- `zabbix_server.conf` contains the DB password: keep it at mode `640`.
