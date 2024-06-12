# shellcheck shell=bash

test_connection () {
    # Resolve HEALTH_CHECK_HOST if domain
    if (ipcalc -c "$HEALTH_CHECK_HOST" > /dev/null 2>&1); then
        health_check_ip=$HEALTH_CHECK_HOST
    else
        health_check_ip="$(dig +short "$HEALTH_CHECK_HOST" | head -n 1)"
        echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] $HEALTH_CHECK_HOST resolved to $health_check_ip"
    fi
    
    echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Route: $(ip r get "$health_check_ip" | head -n 1)"

    if (ping -c 1 "$health_check_ip" > /dev/null 2>&1); then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Ping to $health_check_ip succeeded"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Ping to $health_check_ip failed"
    fi

    # Resolve VPN_REMOTE if domain
    if [[ -n "$VPN_REMOTE_IP" ]]; then
        vpn_remote_ip="$VPN_REMOTE_IP"
    elif (ipcalc -c "$VPN_REMOTE" > /dev/null 2>&1); then
        vpn_remote_ip=$VPN_REMOTE
    else
        vpn_remote_ip="$(dig +short "$VPN_REMOTE" | head -n 1)"
        echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] $VPN_REMOTE resolved to $vpn_remote_ip"
    fi

    if (ping -w 1 -c 1 -I "$DOCKER_INTERFACE" "$vpn_remote_ip" > /dev/null 2>&1); then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Ping to $vpn_remote_ip via $DOCKER_INTERFACE succeeded"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Ping to $vpn_remote_ip via $DOCKER_INTERFACE failed"
    fi
}

stop_container() {
    s6-svc -k -d /run/service/service-qbittorrent/ >/dev/null 2>&1
    s6-svc -k -d /run/service/service-healthcheck/ >/dev/null 2>&1

    # Killing the service doesn't kill the qbittorrent-nox child process
    killall qbittorrent-nox >/dev/null 2>&1

    sleep infinity
}

print_exit_info () {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR INFO] 'ip addr show' output:"
	echo "--------------------"
	ip addr show
	echo "--------------------"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR INFO] 'ip route show table main' output:"
	echo "--------------------"
	ip route show table main
	echo "--------------------"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR INFO] 'ip rule' output:"
	echo "--------------------"
	ip rule
	echo "--------------------"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR INFO] 'netstat -lpn' output:"
	echo "--------------------"
	netstat -lpn
	echo "--------------------"
}