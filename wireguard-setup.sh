route_vpn () {
cat << EOF > /etc/hotplug.d/iface/30-vpnroute
#!/bin/sh

ip route add table vpn default dev wg0
EOF
}

add_wg() {
    printf "\033[32;1mConfigure WireGuard\033[0m\n"
    if opkg list-installed | grep -q wireguard-tools; then
        echo "Wireguard already installed"
    else
        echo "Installed wg..."
        opkg install wireguard-tools
    fi

    route_vpn

    read -r -p "Enter the private key (from [Interface]):"$'\n' WG_PRIVATE_KEY

    while true; do
        read -r -p "Enter internal IP address with subnet, example 192.168.100.5/24 (from [Interface]):"$'\n' WG_IP
        if echo "$WG_IP" | egrep -oq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+$'; then
            break
        else
            echo "This IP is not valid. Please repeat"
        fi
    done

    read -r -p "Enter the public key (from [Peer]):"$'\n' WG_PUBLIC_KEY
    read -r -p "If use PresharedKey, Enter this (from [Peer]). If your don't use leave blank:"$'\n' WG_PRESHARED_KEY
    read -r -p "Enter Endpoint host without port (Domain or IP) (from [Peer]):"$'\n' WG_ENDPOINT

    read -r -p "Enter Endpoint host port (from [Peer]) [51820]:"$'\n' WG_ENDPOINT_PORT
    WG_ENDPOINT_PORT=${WG_ENDPOINT_PORT:-51820}
    if [ "$WG_ENDPOINT_PORT" = '51820' ]; then
        echo $WG_ENDPOINT_PORT
    fi

    uci set network.wg0=interface
    uci set network.wg0.proto='wireguard'
    uci set network.wg0.private_key=$WG_PRIVATE_KEY
    uci set network.wg0.listen_port='51820'
    uci set network.wg0.addresses=$WG_IP

    if ! uci show network | grep -q wireguard_wg0; then
        uci add network wireguard_wg0
    fi
    uci set network.@wireguard_wg0[0]=wireguard_wg0
    uci set network.@wireguard_wg0[0].name='wg0_client'
    uci set network.@wireguard_wg0[0].public_key=$WG_PUBLIC_KEY
    uci set network.@wireguard_wg0[0].preshared_key=$WG_PRESHARED_KEY
    uci set network.@wireguard_wg0[0].route_allowed_ips='0'
    uci set network.@wireguard_wg0[0].persistent_keepalive='25'
    uci set network.@wireguard_wg0[0].endpoint_host=$WG_ENDPOINT
    uci set network.@wireguard_wg0[0].allowed_ips='0.0.0.0/0'
    uci set network.@wireguard_wg0[0].endpoint_port=$WG_ENDPOINT_PORT
    uci commit
}

add_wg

printf "\033[32;1mRestart network\033[0m\n"
/etc/init.d/network restart

printf "\033[32;1mDone\033[0m\n"
