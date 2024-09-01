#!/bin/sh

# Placeholder definitions for interactively defined variables
WG_PRIVATE_KEY="your_private_key_here"
WG_IP="192.168.100.5/24"  # Example: 192.168.100.5/24
WG_PUBLIC_KEY="your_public_key_here"
WG_PRESHARED_KEY=""  # Leave empty if not used
WG_ENDPOINT="your_endpoint_here"  # Example: vpn.example.com
WG_ENDPOINT_PORT="51820"  # Default WireGuard port, can be changed if needed

TUNNEL="wg"  # Name for the tunnel interface

# System Details
MODEL=$(grep machine /proc/cpuinfo | cut -d ':' -f 2)
RELEASE=$(grep OPENWRT_RELEASE /etc/os-release | awk -F '"' '{print $2}')
VERSION_ID=$(grep VERSION_ID /etc/os-release | awk -F '"' '{print $2}' | awk -F. '{print $1}')

# Check if OpenWRT version is compatible
if [ "$VERSION_ID" -ne 23 ]; then
    echo "Script only supports OpenWRT 23.05"
    exit 1
fi

# Install necessary packages if not already installed
opkg update
opkg list-installed | grep -q wireguard-tools || opkg install wireguard-tools
opkg list-installed | grep -q curl || opkg install curl
opkg list-installed | grep -q nano || opkg install nano

# Configure WireGuard Interface
if ! uci show network.wg0 &>/dev/null; then
    uci set network.wg0=interface
    uci set network.wg0.proto='wireguard'
    uci set network.wg0.private_key="$WG_PRIVATE_KEY"
    uci set network.wg0.listen_port='51820'
    uci set network.wg0.addresses="$WG_IP"
else
    echo "WireGuard interface wg0 already configured."
fi

# Configure WireGuard Peer
if ! uci show network.@wireguard_wg0[0] &>/dev/null; then
    uci add network wireguard_wg0
    uci set network.@wireguard_wg0[-1]=wireguard_wg0
    uci set network.@wireguard_wg0[-1].public_key="$WG_PUBLIC_KEY"
    [ -n "$WG_PRESHARED_KEY" ] && uci set network.@wireguard_wg0[-1].preshared_key="$WG_PRESHARED_KEY"
    uci set network.@wireguard_wg0[-1].route_allowed_ips='0'
    uci set network.@wireguard_wg0[-1].persistent_keepalive='25'
    uci set network.@wireguard_wg0[-1].endpoint_host="$WG_ENDPOINT"
    uci set network.@wireguard_wg0[-1].allowed_ips='0.0.0.0/0'
    uci set network.@wireguard_wg0[-1].endpoint_port="$WG_ENDPOINT_PORT"
    uci commit network
else
    echo "WireGuard peer already configured."
fi

# Create a routing table for VPN if not already present
grep -q "99 vpn" /etc/iproute2/rt_tables || echo "99 vpn" >> /etc/iproute2/rt_tables

# Configure firewall zone for WireGuard
if ! uci show firewall | grep -q "@zone.*name='$TUNNEL'"; then
    uci add firewall zone
    uci set firewall.@zone[-1].name="$TUNNEL"
    uci set firewall.@zone[-1].network='wg0'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
    uci set firewall.@zone[-1].family='ipv4'
    uci commit firewall
else
    echo "Firewall zone '$TUNNEL' already exists."
fi

# Configure forwarding from LAN to WireGuard zone
if ! uci show firewall | grep -q "@forwarding.*dest='$TUNNEL'"; then
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest="$TUNNEL"
    uci commit firewall
else
    echo "Forwarding from LAN to '$TUNNEL' already exists."
fi

# Create IP set and mark rule for domain-based routing
if ! uci show firewall | grep -q "@ipset.*name='vpn_domains'"; then
    uci add firewall ipset
    uci set firewall.@ipset[-1].name='vpn_domains'
    uci set firewall.@ipset[-1].match='dst_net'
    uci commit firewall
else
    echo "IP set 'vpn_domains' already exists."
fi

if ! uci show firewall | grep -q "@rule.*name='mark_domains'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='mark_domains'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='*'
    uci set firewall.@rule[-1].proto='all'
    uci set firewall.@rule[-1].ipset='vpn_domains'
    uci set firewall.@rule[-1].set_mark='0x1'
    uci set firewall.@rule[-1].target='MARK'
    uci set firewall.@rule[-1].family='ipv4'
    uci commit firewall
else
    echo "Firewall rule 'mark_domains' already exists."
fi

# Configure dnsmasq-full for domain-based routing
if ! opkg list-installed | grep -q dnsmasq-full; then
    opkg install dnsmasq-full
    /etc/init.d/dnsmasq restart
else
    echo "dnsmasq-full already installed."
fi

# Set up a script to fetch domain lists and reload DNS settings
if [ ! -f /etc/init.d/getdomains ]; then
    cat << EOF > /etc/init.d/getdomains
#!/bin/sh /etc/rc.common

START=99

start () {
    DOMAINS=https://raw.githubusercontent.com/exbor/allow-domains/main/Russia/inside-dnsmasq-nfset.lst
    curl -f \$DOMAINS --output /tmp/dnsmasq.d/domains.lst
    if dnsmasq --conf-file=/tmp/dnsmasq.d/domains.lst --test 2>&1 | grep -q "syntax check OK"; then
        /etc/init.d/dnsmasq restart
    fi
}
EOF

    chmod +x /etc/init.d/getdomains
    /etc/init.d/getdomains enable
elses
    echo "getdomains script already exists."
fi

# Schedule domain list updates if not already scheduled
if ! crontab -l | grep -q "/etc/init.d/getdomains start"; then
    (crontab -l; echo "0 */8 * * * /etc/init.d/getdomains start") | crontab -
else
    echo "Cron job for getdomains already exists."
fi

# Restart the network to apply all changes
/etc/init.d/network restart

echo "WireGuard VPN configuration completed successfully."
