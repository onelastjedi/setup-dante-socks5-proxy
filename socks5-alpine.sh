#!/bin/sh

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0;0m' # No color

# Use colored echo
c_echo () { eval "echo -e \$$1\$2\$NC"; }

# Use big echo
b_echo () { echo "-----------------------> $1"; }

# Get default ip () 
get_default_ip () {
	def_ip=$(ifconfig | grep eth0 -A1 | grep inet | awk '{print $2}')
}

# Create the configuration file
create_sockd_config () {
	b_echo "Creating proxy config file.."
cat > /etc/sockd.conf <<EOF
logoutput: /var/log/sockd.log
internal: 0.0.0.0 port = $port
external: $iface
socksmethod: username
resolveprotocol: fake
user.privileged: root
user.notprivileged: nobody
client pass {
	from: 0/0 to: 0/0
	log: connect disconnect error
}
socks pass {
	from: 0/0 to: 0/0
	log: connect disconnect error
}
EOF
}

# Configure firewall rules
update_iptables () {
	b_echo "Updating iptables rules."
	if ! iptables -L | grep -q "tcp dpt:$port"; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    fi
}

# Install software
install_pkgs () {
	b_echo "Installing packages."
	apk update
	apk add dante-server iptables curl
    c_echo "GREEN" "Dante SOCKS5 server installed successfully."
}

# Create the log file before starting the service
create_log_file () {
	b_echo "Creating log file."
	touch /var/log/sockd.log
	chown nobody:nogroup /var/log/sockd.log
}

# Automatically detect the primary network interface
detect_iface () {
	b_echo "Detecting primary network interface."
	iface=$(ip route | grep default | awk '{print $5}')
	if [ -z $iface ]; then
		c_echo "RED" "Could not detect the primary network interface. Please check your network settings."
		exit 1
	fi
}

# Start services
start_services () {
	b_echo "Starting SOCK5 server."
	rc-service sockd restart &> /dev/null
	is_started=$(rc-service sockd status -s | grep started | awk '{print $3}')
	if [ -z $is_started ]; then
		c_echo "RED" "Failed to start the SOCKS5 server. Please check the logs for more details: /var/log/sockd.log"
		exit 1
	fi
	c_echo "GREEN" "Socks5 server has been reconfigured and is running on port - $port."
}

# Enable services on boot
enable_on_boot () {
	for svc in sockd; do
		rc-update add $svc default &> /dev/null
	done
}

# Add user
add_user () {
	b_echo "Adding user."
	if [ $add_user ]; then
		c_echo "CYAN" "Please enter the username for the SOCKS5 proxy:"
		read username
		c_echo "CYAN" "Please enter the password for the SOCKS5 proxy:"
		read -s password
		if id $username &> /dev/null; then
			c_echo "YELLOW" "User @$username already exists. Updating password."
		else
			adduser -s /sbin/nologin -D -H $username
			c_echo "GREEN" "User @$username created successfully."
		fi
		echo "$username:$password" | chpasswd
		c_echo "GREEN" "Password updated successfully for user: $username."
	fi
}

show_proxy_info () {
cat <<EOF

================================================

SOCKS5 proxy server is now ready for use!

Connect to your new proxy with these details:

Server IP: $def_ip
Port: $port
Username: $username
Password: $password
Url: https://t.me/socks?server=$(hostname)&port=$port&user=$username&pass=$password

================================================

EOF
}

# Check if danted is installed
if command -v sockd &> /dev/null; then
	c_echo "GREEN" "Dante SOCKS5 server is already installed."
else
    c_echo "YELLOW" "Dante SOCKS5 server is not installed on this system."
    c_echo "CYAN" "Note: Port 1080 is commonly used for SOCKS5 proxy. However, it may be blocked by your ISP or server provider. If this happens, choose an alternate port."
    c_echo "CYAN" "Please enter the port for the SOCKS5 proxy (default: 1080):"
    read port
    port=${port:-1080}
    if ! [[ $port =~ ^[0-9]+$ ]] || [ $port -lt 1 -o $port -gt 65535 ]; then
        c_echo "RED" "Invalid port. Please enter a number between 1 and 65535."
        exit 1
    fi
    reconfigure=true
    add_user=true
fi

# Install or Reconfigure Dante
if [ $reconfigure ]; then
	install_pkgs
	create_log_file
	detect_iface
	create_sockd_config
	update_iptables
	add_user
	start_services
	enable_on_boot
	get_default_ip
	show_proxy_info
fi
