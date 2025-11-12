#!/bin/bash

# This script is for Assignment 2.
# THis will configure your Server1 with network, hosts, software, and users.
# Just run this on server 1

echo "Starting the script on Date: $(date)"

# Part 1: Fix the network (set IP to 192.168.16.21 on eth0)
echo "Checking network..."
INTERFACE="eth0"  # This is gonna be your main network card from ip a, most probably
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

# Checking if the IP is already set
if grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
    echo "Network is already set. Skipping."
else
    echo "Setting network IP to 192.168.16.21/24..."
    # Make sure there's  a backup
    cp "$NETPLAN_FILE" "$NETPLAN_FILE.backup"
    # Config the new IP settings
    echo "    $INTERFACE:" >> "$NETPLAN_FILE"
    echo "      addresses:" >> "$NETPLAN_FILE"
    echo "        - 192.168.16.21/24" >> "$NETPLAN_FILE"
    echo "      nameservers:" >> "$NETPLAN_FILE"
    echo "        addresses: [8.8.8.8, 8.8.4.4]" >> "$NETPLAN_FILE"
    # Apply the changes
    netplan apply
    echo "Network updated."
fi

# Part 2: Update /etc/hosts file
echo "Checking /etc/hosts..."
HOSTS_FILE="/etc/hosts"

if grep -q "192.168.16.21.*server1" "$HOSTS_FILE"; then
    echo "/etc/hosts is already updated. Skipping."
else
    echo "Adding server1 to /etc/hosts..."
    # Remove old server1 lines if any
    sed -i '/server1/d' "$HOSTS_FILE"
    # Add the new line
    echo "192.168.16.21 server1" >> "$HOSTS_FILE"
    echo "/etc/hosts updated."
fi

# Part 3: Install software (Apache2 and Squid)
echo "Checking Apache2..."
if systemctl is-active apache2; then
    echo "Apache2 is already running. Skipping."
else
    echo "Installing Apache2..."
    apt update
    apt install -y apache2
    systemctl enable apache2
    systemctl start apache2
    echo "Apache2 installed and started."
fi

echo "Checking Squid..."
if systemctl is-active squid; then
    echo "Squid is already running. Skipping."
else
    echo "Installing Squid..."
    apt install -y squid
    systemctl enable squid
    systemctl start squid
    echo "Squid installed and started."
fi

# Part 4: Create users
echo "Creating users..."
USERS="dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda"

for USER in $USERS; do  # Loop through each user
    echo "Working on user: $USER"
    
    # Check if user exists
    if id "$USER" > /dev/null 2>&1; then
        echo "User $USER already exists. Skipping creation."
    else
        echo "Creating user $USER..."
        useradd -m -d "/home/$USER" -s /bin/bash "$USER"
        echo "User $USER created."
    fi
    
    # Make sure they have the right home and shell
    usermod -d "/home/$USER" -s /bin/bash "$USER"
    
    # Special for dennis: add to sudo group
    if [ "$USER" = "dennis" ]; then
        if groups "$USER" | grep -q sudo; then
            echo "Dennis already has sudo. Skipping."
        else
            echo "Adding dennis to sudo group..."
            usermod -aG sudo "$USER"
            echo "Dennis added to sudo."
        fi
    fi
    
    # Set up SSH keys
    SSH_DIR="/home/$USER/.ssh"
    AUTH_KEYS="$SSH_DIR/authorized_keys"
    
    # Create .ssh folder if needed
    mkdir -p "$SSH_DIR"
    chown "$USER:$USER" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    # Generate RSA key if not there
    if [ ! -f "$SSH_DIR/id_rsa" ]; then
        echo "Making RSA key for $USER..."
        su - "$USER" -c "ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''"
        echo "RSA key made."
    fi
    
    # Generate Ed25519 key if not there
    if [ ! -f "$SSH_DIR/id_ed25519" ]; then
        echo "Making Ed25519 key for $USER..."
        su - "$USER" -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''"
        echo "Ed25519 key made."
    fi
    
    # Add the user's own keys to authorized_keys
    if ! grep -q "$(cat $SSH_DIR/id_rsa.pub)" "$AUTH_KEYS" 2>/dev/null; then
        cat "$SSH_DIR/id_rsa.pub" >> "$AUTH_KEYS"
    fi
    if ! grep -q "$(cat $SSH_DIR/id_ed25519.pub)" "$AUTH_KEYS" 2>/dev/null; then
        cat "$SSH_DIR/id_ed25519.pub" >> "$AUTH_KEYS"
    fi
    
    # Special for dennis: add the extra key
    if [ "$USER" = "dennis" ]; then
        EXTRA_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
        if ! grep -q "$EXTRA_KEY" "$AUTH_KEYS"; then
            echo "$EXTRA_KEY" >> "$AUTH_KEYS"
            echo "Extra key added for dennis."
        fi
    fi
    
    # Fix permissions on authorized_keys
    chown "$USER:$USER" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    echo "SSH keys set for $USER."
done

echo "Your script done!"
echo "Finished at: $(date)"
