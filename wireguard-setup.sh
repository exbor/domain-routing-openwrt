route_vpn () {
cat << EOF > /etc/hotplug.d/iface/30-vpnroute
#!/bin/sh

ip route add table vpn default dev wg0
EOF
}

# remove_forwarding() {
#     if [ ! -z "$forward_id" ]; then
#         while uci -q delete firewall.@forwarding[$forward_id]; do :; done
#     fi
# }

add_zone() {
    if uci show firewall | grep -q "@zone.*name='wg'"; then
        printf "\033[32;1mZone already exist\033[0m\n"
    else
        printf "\033[32;1mCreate zone\033[0m\n"

        zone_wg_id=$(uci show firewall | grep -E '@zone.*wg0' | awk -F '[][{}]' '{print $2}' | head -n 1)
        if [ "$zone_wg_id" == 0 ] || [ "$zone_wg_id" == 1 ]; then
            printf "\033[32;1mwg0 zone has an identifier of 0 or 1. That's not ok. Fix your firewall. lan and wan zones should have identifiers 0 and 1. \033[0m\n"
            exit 1
        fi
        if [ ! -z "$zone_wg_id" ]; then
            while uci -q delete firewall.@zone[$zone_wg_id]; do :; done
        fi

        uci add firewall zone
        uci set firewall.@zone[-1].name="wg"
        uci set firewall.@zone[-1].network='wg0'
        uci set firewall.@zone[-1].forward='REJECT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='REJECT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall
    fi
    
    if uci show firewall | grep -q "@forwarding.*name='wg-lan'"; then
        printf "\033[32;1mForwarding already configured\033[0m\n"
    else
        printf "\033[32;1mConfigured forwarding\033[0m\n"
        # Delete exists forwarding
        # if [[ $TUNNEL != "wg" ]]; then
        #     forward_id=$(uci show firewall | grep -E "@forwarding.*dest='wg'" | awk -F '[][{}]' '{print $2}' | head -n 1)
        #     remove_forwarding
        # fi

        # if [[ $TUNNEL != "awg" ]]; then
        #     forward_id=$(uci show firewall | grep -E "@forwarding.*dest='awg'" | awk -F '[][{}]' '{print $2}' | head -n 1)
        #     remove_forwarding
        # fi

        # if [[ $TUNNEL != "ovpn" ]]; then
        #     forward_id=$(uci show firewall | grep -E "@forwarding.*dest='ovpn'" | awk -F '[][{}]' '{print $2}' | head -n 1)
        #     remove_forwarding
        # fi

        # if [[ $TUNNEL != "singbox" ]]; then
        #     forward_id=$(uci show firewall | grep -E "@forwarding.*dest='singbox'" | awk -F '[][{}]' '{print $2}' | head -n 1)
        #     remove_forwarding
        # fi

        # if [[ $TUNNEL != "tun2socks" ]]; then
        #     forward_id=$(uci show firewall | grep -E "@forwarding.*dest='tun2socks'" | awk -F '[][{}]' '{print $2}' | head -n 1)
        #     remove_forwarding
        # fi

        uci add firewall forwarding
        uci set firewall.@forwarding[-1]=forwarding
        uci set firewall.@forwarding[-1].name="wg-lan"
        uci set firewall.@forwarding[-1].dest="wg"
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].family='ipv4'
        uci commit firewall
    fi
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

add_zone

printf "\033[32;1mRestart network\033[0m\n"
/etc/init.d/network restart

printf "\033[32;1mDone\033[0m\n"
