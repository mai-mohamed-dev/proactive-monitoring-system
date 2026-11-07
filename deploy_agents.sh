# This script is intended to be run on a VM that is needed to be monitored by Zabbix. 
# It installs and configures the Zabbix agent, and registers the host with the Zabbix server.
# copy this script to the VM and run it as root or with sudo privileges. "bash deploy_agents.sh"
# this written for CentOS 9 Stream, but should work on other RHEL-based distros with minor modifications.

#!/bin/bash
set -e

SERVER_IP="192.168.56.10"       # Zabbix server
NAME=$(hostname -s)            # unique name of this VM in Zabbix
METADATA="linux-server"        # must match the auto-registration action condition
CONF="/etc/zabbix/zabbix_agentd.conf"
LOG="/var/log/zabbix/zabbix_agentd.log"

case "$NAME" in localhost|"") echo "Set a real hostname first"; exit 1 ;; esac

# 1. Check if Zabbix Agent 7.0 is already installed and running the correct version
CURRENT_VERSION=$(zabbix_agentd -V 2>/dev/null | head -n1 | grep -oP '7\.0\.\d+' || echo "")

if [ -z "$CURRENT_VERSION" ]; then
    echo "[INFO] Zabbix Agent 7.0 not found. Installing..."
    
    # Ensure EPEL release is present and exclude zabbix from it (with proper sudo)
    sudo dnf install -y epel-release
    [ -f /etc/yum.repos.d/epel.repo ] && ! sudo grep -q '^excludepkgs=zabbix' /etc/yum.repos.d/epel.repo \
      && sudo sed -i '/^\[epel\]/a excludepkgs=zabbix*' /etc/yum.repos.d/epel.repo

    # Install Zabbix 7.0 repository and agent package cleanly
    sudo dnf install -y https://repo.zabbix.com/zabbix/7.0/centos/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
    sudo dnf clean all
    sudo dnf makecache
    sudo dnf install -y zabbix-agent
else
    echo "[INFO] Zabbix Agent 7.0 is already installed ($CURRENT_VERSION). Skipping installation."
fi

# Verify agent version matches 7.0
zabbix_agentd -V | head -n1 | grep -q ' 7\.0\.' || { echo "[ERROR] agent is not 7.0"; zabbix_agentd -V | head -n1; exit 1; }

# 2. Configuration (safely updates or replaces existing values using sudo)
sudo sed -i -E '/^(Server|ServerActive|Hostname|HostnameItem|HostMetadata)=/d' "$CONF"
printf 'Server=%s\nServerActive=%s\nHostname=%s\nHostMetadata=%s\n' \
  "$SERVER_IP" "$SERVER_IP" "$NAME" "$METADATA" | sudo tee -a "$CONF" >/dev/null

# 3. Start now and on every boot
sudo systemctl enable zabbix-agent
sudo systemctl restart zabbix-agent
echo "Agent active: Hostname=$NAME HostMetadata=$METADATA Server=$SERVER_IP"