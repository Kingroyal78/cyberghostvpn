#!/bin/bash

	config_ini=/home/root/.cyberghost/config.ini #CyberGhost Auth token

	enable_dns_port () {
		echo "Allowing PORT 53 - IN/OUT"	
		sudo ufw allow out 53 > /dev/null 2>&1 #Allow port 53 on all interface for initial VPN connection
		sudo ufw allow in 53 > /dev/null 2>&1
	}
	
	disable_dns_port () {
		echo "Blocking PORT 53 - IN/OUT"
		sudo ufw delete allow out 53 > /dev/null 2>&1 #Remove Local DNS Port to prevent leaks
		sudo ufw delete allow in 53 > /dev/null 2>&1
	}
	
	startup () {
		echo "CyberGhostVPN - Docker Edition"
		echo "----------------------------------------------------------"
		echo "	Created By: Tyler McPhee"
		echo "	GitHub: https://github.com/tmcphee/cyberghostvpn"
		echo "	DockerHub: https://hub.docker.com/r/tmcphee/cyberghostvpn"
		echo "	"
		echo "	Debian:${linux_version} | CyberGhost:${cyberghost_version} | ${script_version}"
		echo "----------------------------------------------------------"
		
		echo "**************User Defined Variables**************"
		
		if [ -n "$ACC" ]; then
			echo "	ACC: [PASSED - NOT SHOWN]"
		fi
		if [ -n "$PASS" ]; then
			echo "	PASS: [PASSED - NOT SHOWN]"
		fi
		
		if [ -n "$COUNTRY" ]; then
			echo "	COUNTRY: ${COUNTRY}"
		fi
		if [ -n "$NETWORK" ]; then
			echo "	NETWORK: ${NETWORK}"
		fi
		if [ -n "$WHITELISTPORTS" ]; then
			echo "	WHITELISTPORTS: ${WHITELISTPORTS}"
		fi
		if [ -n "$ARGS" ]; then
			echo "	ARGS: ${ARGS}"
		fi
		if [ -n "$NAMESERVER" ]; then
			echo "	NAMESERVER: ${NAMESERVER}"
		fi
		if [ -n "$PROTOCOL" ]; then
			echo "	PROTOCOL: ${PROTOCOL}"
		fi
		if [ -n "$PROXY" ]; then
			echo "	PROXY: ${PROXY}"
		fi

		echo "**************************************************"
		
	}
	
	ip_stats () {
		str="$(cat /etc/resolv.conf)"
		value=${str#* }
		
		echo "***********CyberGhost Connection Info***********"
		echo "	IP: ""$(curl -s -m 10 https://ipinfo.io/ip -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	CITY: ""$(curl -s -m 10 https://ipinfo.io/city -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	REGION: ""$(curl -s -m 10 https://ipinfo.io/region -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	COUNTRY: ""$(curl -s -m 10 https://ipinfo.io/country -H "Cache-Control: no-cache, no-store, must-revalidate")"
		echo "	DNS: ${value}"
		echo "************************************************"
	}
	
	#Squid is managed directly. The systemctl replacement loses track of it after a few hours
	#[it treats /run/squid.pid as stale once /proc/1/status gets a newer mtime] and stop does nothing
	proxy_stop () {
		echo "Stopping HTTP Proxy..."
		sudo pkill -x squid > /dev/null 2>&1
		for i in $(seq 1 10) #Wait for squid to exit and release port 3128
		do
			pgrep -x squid > /dev/null || break
			sleep 1
		done
		sudo pkill -9 -x squid > /dev/null 2>&1
		rm -f /run/squid.pid
		echo "HTTP Proxy stopped"
	}

	proxy_start () {
		echo "Starting HTTP Proxy..."
		sudo squid -YC > /dev/null 2>&1
		for i in $(seq 1 10) #Wait for squid to listen on port 3128
		do
			if ss -ltn 'sport = :3128' | grep -q 3128; then
				echo "HTTP Proxy running on port 3128"
				return 0
			fi
			sleep 1
		done
		echo "[E4] HTTP Proxy failed to start. See /var/log/squid/cache.log"
		return 1
	}

	#Originated from Run.sh. Migrated for speed improvements
	cyberghost_start () {
		#Stop Proxy service to prevent dns leaks
		if [ -n "${PROXY}" ]; then
			if [ "${PROXY}" == "True" ]; then
				proxy_stop
			fi
		fi
		enable_dns_port
		#Check for CyberGhost Auth file
		if [ -f "$config_ini" ]; then
	
			# Check if country is set. Default to US
			if ! [ -n "$COUNTRY" ]; then
				echo "Country variable not set. Defaulting to US"
				export COUNTRY="US"
			fi
				
			# Check if protocol is set. Default WireGuard
			if ! [ -n "$PROTOCOL" ]; then
				export PROTOCOL="wireguard"
			fi
				
			#Launch and connect to CyberGhost VPN
			sudo cyberghostvpn --connect --country-code "$COUNTRY" --"$PROTOCOL" "$ARGS"
			
			# Add CyberGhost nameserver to resolv for DNS
			# Add Nameserver via env variable $NAMESERVER
			if [ -n "$NAMESERVER" ]; then
				echo 'nameserver ' "$NAMESERVER" > /etc/resolv.conf
			else
				# CyberGhost Smart DNS only serves IPs registered on the account and answers 0.0.0.1
				# for every domain when queried over the VPN. Use CloudFlare through the tunnel instead
				echo 'nameserver 1.1.1.1' > /etc/resolv.conf
			fi
		fi
		disable_dns_port
		#Enable Proxy service
		if [ -n "${PROXY}" ]; then
			if [ "${PROXY}" == "True" ]; then
				proxy_start
			fi
		fi
		ip_stats
	}
	
	#Check if the internet is reachable. Ping CloudFlare then Google so one filtered target doesn't trigger a reconnect
	check_up() {
		for host in 1.1.1.1 8.8.8.8
		do
			if ping -c1 -W5 "$host" > /dev/null 2>&1; then
				return 0
			fi
		done
		return 1
	}
	if ! [ -n "$FIREWALL" ]; then
		export FIREWALL="True"
	fi
	
	startup
	
	#Check if CyberGhost CLI is installed. If not install it
	FILE=/usr/local/cyberghost/uninstall.sh
	if [ ! -f "$FILE" ]; then
		echo "CyberGhost CLI not installed. Installing..."
		bash /install.sh
		echo "Installed"
	fi
	
	#Run Firewall if Enabled. Default Enabled
	sysctl -w net.ipv6.conf.all.disable_ipv6=1 #Disable IPV6
	sysctl -w net.ipv6.conf.default.disable_ipv6=1
	sysctl -w net.ipv6.conf.lo.disable_ipv6=1
	sysctl -w net.ipv6.conf.eth0.disable_ipv6=1
	sysctl -w net.ipv4.ip_forward=1
	
	
	if [[ ${FIREWALL,,} == *"true"* ]]; then
		sudo ufw enable #Start Firewall

		FIREWALL_FILE=/.FIREWALL.cg
		if [ ! -f "$FIREWALL_FILE" ]; then
			echo "Initiating Firewall First Time Setup..."
				
			sudo ufw disable #Stop Firewall
			sudo ufw default deny outgoing > /dev/null 2>&1							#Deny All traffic by default on all interfaces
			sudo ufw default deny incoming > /dev/null 2>&1
			sudo ufw allow out on cyberghost from any to any > /dev/null 2>&1 		#Allow All over cyberghost interface
			sudo ufw allow in on cyberghost from any to any > /dev/null 2>&1
			sudo ufw allow in 1337 > /dev/null 2>&1 								#Allow port 1337 for CyberGhost Communication
			sudo ufw allow out 1337 > /dev/null 2>&1
			sudo ufw allow in 891 > /dev/null 2>&1 									#Allow port 1194 for CyberGhost OpenVPN Communication
			sudo ufw allow out 819 > /dev/null 2>&1
			#Allow every IP v2-api.cyberghostvpn.com resolves to. It is behind Cloudflare and the CLI may pick any of them
			for CYBERGHOST_API_IP in $(getent ahostsv4 v2-api.cyberghostvpn.com | awk '/STREAM/{print $1}')
			do
				sudo ufw allow out from any to "$CYBERGHOST_API_IP" > /dev/null 2>&1
				sudo ufw allow in from "$CYBERGHOST_API_IP" to any > /dev/null 2>&1
			done
			
			#Allow all ports in WHITELISTPORTS ENV [Seperate by ',']
			if [ -n "${WHITELISTPORTS}" ]; then
				echo "Setting Whitelisted Ports..."
				IFS=',' read -a array <<< "$WHITELISTPORTS"
				for i in "${array[@]}"
				do
				   echo "Whitelisting Port:" "$i"
				   sudo ufw allow "$i" > /dev/null 2>&1
				done
			fi
			
			sudo ufw enable #Start Firewall
			echo "Firewall Setup Complete"	
			echo 'FIREWALL ACTIVE WHEN FILE EXISTS' > .FIREWALL.cg
		fi
	else
		sudo ufw disable #Stop Firewall
	fi
	
	#Login to account if config not exist
	if [ ! -f "$config_ini" ]; then
		echo "Logging into CyberGhost..."
		
		#Check for CyberGhost Credentials and Login
		if [ -n "$ACC" ] && [ -n "$PASS" ]; then
			enable_dns_port
			expect /auth.sh
			disable_dns_port
		else
			echo "[E1] Can't Login. User didn't provide login credentials. Set the ACC and PASS ENV variables and try again." 
			exit
		fi
	else
		#Verify the config.ini has successfully created the Account and assigned a Device
		echo "Verifying Login Auth..."
		if ! grep -qiF '[device]' $config_ini; then
			echo "Failed"
			rm "$config_ini"
			echo "Logging into CyberGhost..."
			enable_dns_port
			expect /auth.sh
			disable_dns_port
		else
			echo "Passed"
		fi
	fi
	
	if [ -n "${NETWORK}" ]; then
		echo "Adding network route..."
		export LOCAL_GATEWAY=$(ip r | awk '/^def/{print $3}') # Get local Gateway
		ip route add "$NETWORK" via "$LOCAL_GATEWAY" dev eth0 #Enable access to local lan
		echo "$NETWORK" "routed to" "$LOCAL_GATEWAY" "on eth0"
	fi
	
	
	if [ -n "${PROXY}" ]; then
		if [ "${PROXY}" == "True" ]; then
			echo "Seting up HTTP proxy on port 3128..."
			sudo ufw allow in 3128 > /dev/null 2>&1 #Enable Proxy Port
			sudo ufw allow out 3128 > /dev/null 2>&1
		else
			echo "Disabling HTTP proxy..."
			sudo ufw deny in 3128 > /dev/null 2>&1 #Disable Proxy Port
			sudo ufw deny out 3128 > /dev/null 2>&1
		fi
	else
		echo "Disabling HTTP proxy..."
		sudo ufw deny in 3128 > /dev/null 2>&1 #Disable Proxy Port
		sudo ufw deny out 3128 > /dev/null 2>&1
	fi
	
	#WIREGUARD START AND WATCH
	cyberghost_start
	fail_count=0 #Failed internet checks in a row
	while true #Watch if Connection is lost then reconnect
	do
		sleep 30
		if [[ $(sudo cyberghostvpn --status | grep 'No VPN connections found.' | wc -l) = "1" ]]; then
			echo '[E2] VPN Connection Lost - Attempting to reconnect....'
			cyberghost_start
			fail_count=0
			continue
		fi

		#WireGuard keeps the interface up when the server stops answering, so E2 never sees a dead tunnel.
		#Check internet reachability on every pass and reconnect after 3 failures in a row [~2 minutes]
		if check_up; then
			fail_count=0
		else
			fail_count=$((fail_count + 1))
			echo "Internet check failed ($fail_count/3)"
			if [ "$fail_count" -ge 3 ]; then
				echo '[E3] Internet not reachable - Restarting VPN...'
				sudo cyberghostvpn --stop
				cyberghost_start
				fail_count=0
			fi
		fi
	done
	
	echo '[FATAL ERROR] - $?'
	
	
#ERROR CODES
#E1 Can't Login to CyberGhost - Credentials not provided
#E2 VPN Connection Lost
#E3 Internet Connection Lost
#E4 HTTP Proxy failed to start
	
