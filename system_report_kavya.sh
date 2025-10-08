!/bin/bash

# A starting command that staes the start of the script
echo "Now let's grab your secret information from your device"

# Displays the  User Information with today's date for easy interface
USER=$(whoami)
HOST=$(hostname)
DATE=$(date)

# This is gonna display the  System Information
OS_INFO=$(grep "^PRETTY_NAME" /etc/os-release)
UPTIME_INFO=$(uptime -p)
CPU_INFO=$(lscpu | awk -F 'Model Name:')
RAM_INFO=$(free -h | grep Mem)
DISK_INFO=$(df -h)
HOST_ADDR=$(ip a | grep 'inet ' | head -1)
GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
DNS_SERVER=$(cat /etc/resolv.conf | grep nameserver | head -1)

# Displays the current system status
USERS_LOGGED_IN=$(who)
DISK_SPACE=$(df -h)
PROCESS_COUNT=$(ps aux | wc -l)
LOAD_AVERAGES=$(uptime | awk -F 'load average:' '{print $2}')
LISTENING_PORTS=$(ss -tuln)
UFW_STATUS=$(sudo ufw status)


cat <<EOL
THis is a SYSTEM REPORT generated for $HOST by $USER on $DATE

System Information
------------------------------------------------------------
OS: $OS_INFO
Uptime: $UPTIME_INFO
CPU: $CPU_INFO
RAM: $RAM_INFO

Disk(s):
$DISK_INFO

Host Address: $HOST_ADDR
Gateway IP: $GATEWAY_IP
DNS Server: $DNS_SERVER

System Status
------------------------------------------------
Users Logged In:
$USERS_LOGGED_IN

Disk Space:
$DISK_SPACE
Process Count: $PROCESS_COUNT
Load Averages: $LOAD_AVERAGES

Listening Network Ports:
$LISTENING_PORTS

UFW Status:
$UFW_STATUS

EOL
