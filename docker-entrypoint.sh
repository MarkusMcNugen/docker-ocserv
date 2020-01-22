#!/bin/bash

# Copy default config files if removed
if [[ ! -e /config/ocserv.conf || ! -e /config/connect.sh || ! -e /config/disconnect.sh ]]; then
	echo "$(date) [err] Required config files are missing. Replacing with default backups!"
	rsync -vzr --ignore-existing "/etc/default/ocserv/" "/config"
fi
chmod a+x /config/*.sh

##### Verify Variables #####
export POWER_USER=$(echo "${POWER_USER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
# Check POWER_USER env var
if [[ ! -z "${POWER_USER}" ]]; then
	echo "$(date) [info] POWER_USER defined as '${POWER_USER}'"
else
	echo "$(date) [warn] POWER_USER not defined,(via -e POWER_USER), defaulting to 'no'"
	export POWER_USER="no"
fi

export LISTEN_PORT=$(echo "${LISTEN_PORT}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
# Check PROXY_SUPPORT env var
if [[ ! -z "${LISTEN_PORT}" ]]; then
	echo "$(date) [info] LISTEN_PORT defined as '${LISTEN_PORT}'"
	echo "$(date) [warn] Make sure you changed the 4443 port in container settings to expose the port you selected!"
else
	echo "$(date) [warn] LISTEN_PORT not defined,(via -e LISTEN_PORT), defaulting to '4443'"
	export LISTEN_PORT="4443"
fi

export TUNNEL_MODE=$(echo "${TUNNEL_MODE}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
# Check PROXY_SUPPORT env var
if [[ ! -z "${TUNNEL_MODE}" ]]; then
	echo "$(date) [info] TUNNEL_MODE defined as '${TUNNEL_MODE}'"
else
	echo "$(date) [warn] TUNNEL_MODE not defined,(via -e TUNNEL_MODE), defaulting to 'all'"
	export TUNNEL_MODE="all"
fi

if [[ ${TUNNEL_MODE} == "all" ]]; then
	echo "$(date) [info] Tunnel mode is all, ignoring TUNNEL_ROUTES. If you want to define specific routes, change TUNNEL_MODE to split-include"
elif [[ ${TUNNEL_MODE} == "split-include" ]]; then
	# strip whitespace from start and end of SPLIT_DNS_DOMAINS
	export TUNNEL_ROUTES=$(echo "${TUNNEL_ROUTES}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	# Check SPLIT_DNS_DOMAINS env var and exit if not defined
	if [[ ! -z "${TUNNEL_ROUTES}" ]]; then
		echo "$(date) [info] TUNNEL_ROUTES defined as '${TUNNEL_ROUTES}'"
	else
		echo "$(date) [err] TUNNEL_ROUTES not defined (via -e TUNNEL_ROUTES), but TUNNEL_MODE is defined as split-include"
	fi
fi

#export PROXY_SUPPORT=$(echo "${PROXY_SUPPORT}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
# Check PROXY_SUPPORT env var
#if [[ ! -z "${PROXY_SUPPORT}" ]]; then
#	echo "$(date) [info] PROXY_SUPPORT defined as '${PROXY_SUPPORT}'"
#else
#	echo "$(date) [warn] PROXY_SUPPORT not defined,(via -e PROXY_SUPPORT), defaulting to 'no'"
#	export PROXY_SUPPORT="no"
#fi

export DNS_SERVERS=$(echo "${DNS_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
# Check DNS_SERVERS env var
if [[ ! -z "${DNS_SERVERS}" ]]; then
		echo "$(date) [info] DNS_SERVERS defined as '${DNS_SERVERS}'"
	else
		echo "$(date) [warn] DNS_SERVERS not defined (via -e DNS_SERVERS), defaulting to Google and FreeDNS name servers"
		export DNS_SERVERS="8.8.8.8,37.235.1.174,8.8.4.4,37.235.1.177"
fi

export SPLIT_DNS_DOMAINS=$(echo "${SPLIT_DNS_DOMAINS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${SPLIT_DNS_DOMAINS}" ]]; then
	# Check SPLIT_DNS_DOMAINS env var
	if [[ ! -z "${SPLIT_DNS_DOMAINS}" ]]; then
		echo "$(date) [info] SPLIT_DNS_DOMAINS defined as '${SPLIT_DNS_DOMAINS}'"
	else
		echo "$(date) [err] SPLIT_DNS_DOMAINS not defined (via -e SPLIT_DNS_DOMAINS)"
	fi
fi


##### Process Variables #####
if [ ${LISTEN_PORT} != "4443" ]; then
	echo "$(date) [info] Modifying the listening port"
	if [[ ${POWER_USER} == "yes" ]]; then
		echo "$(date) [warn] Power user! Listening ports are not being written to ocserv.conf, you must manually modify the conf file yourself!"
	else
		#Find TCP/UDP line numbers and use sed to replace the lines
		TCPLINE = $(grep -rne 'tcp-port =' ocserv.conf | grep -Eo '^[^:]+')
		UDPLINE = $(grep -rne 'udp-port =' ocserv.conf | grep -Eo '^[^:]+')
		sed -i "$(TCPLINE)s/.*/tcp-port = ${LISTEN_PORT}/" /config/ocserv.conf
		sed -i "$(UDPLINE)s/.*/tcp-port = ${LISTEN_PORT}/" /config/ocserv.conf
	fi
fi

if [[ ${TUNNEL_MODE} == "all" ]]; then
	echo "$(date) [info] Tunneling all traffic through VPN"
	if [[ ${POWER_USER} == "yes" ]]; then
		echo "$(date) [warn] Power user! Routes are not being written to ocserv.conf, you must manually modify the conf file yourself!"
	else
		sed -i '/^route=/d' /config/ocserv.conf
	fi
elif [[ ${TUNNEL_MODE} == "split-include" ]]; then
	echo "$(date) [info] Tunneling routes $TUNNEL_ROUTES through VPN"
	if [[ ${POWER_USER} == "yes" ]]; then
		echo "$(date) [warn] Power user! Routes are not being written to ocserv.conf, you must manually modify the conf file yourself!"
	else
		sed -i '/^route=/d' /config/ocserv.conf
		# split comma seperated string into list from TUNNEL_ROUTES env variable
		IFS=',' read -ra tunnel_route_list <<< "${TUNNEL_ROUTES}"
		# process name servers in the list
		for tunnel_route_item in "${tunnel_route_list[@]}"; do
			tunnel_route_item=$(echo "${tunnel_route_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
			IFS='/' read -ra ip_subnet_list <<< "${tunnel_route_item}"
			STRLENGTH=$(echo -n ${ip_subnet_list[1]} | wc -m)
			if [[ $STRLENGTH > "2" ]]; then
				echo "$(date) [info] Full subnet mask detected in route ${tunnel_route_item}"
				IP=$(sipcalc ${ip_subnet_list[0]} ${ip_subnet_list[1]} | awk '/Host address/ {print $4; exit}')
				NETMASK=$(sipcalc ${ip_subnet_list[0]} ${ip_subnet_list[1]} | awk '/Network mask/ {print $4; exit}')
			else
				echo "$(date) [info] CIDR submet mask detected in route ${tunnel_route_item}"
				IP=$(ipcalc -b ${tunnel_route_item} | awk '/Address/ {print $2}')
				NETMASK=$(ipcalc -b ${tunnel_route_item} | awk '/Netmask/ {print $2}')
			fi
			#IP=$(ipcalc -b ${tunnel_route_item} | awk '/Address/ {print $2; exit}')
			#NETMASK=$(ipcalc -b ${tunnel_route_item} | awk '/Netmask/ {print $2; exit}')
			TUNDUP=$(cat /config/ocserv.conf | grep "route=${IP}/${NETMASK}")
			if [[ -z "$TUNDUP" ]]; then
				echo "$(date) [info] Adding route=$IP/$NETMASK to ocserv.conf"
				echo "route=$IP/$NETMASK" >> /config/ocserv.conf
			fi
		done
	fi
fi

# Process PROXY_SUPPORT env var
#if [[ ${POWER_USER} == "yes" ]]; then
#	echo "$(date) Power user! Proxy support not being written to ocserv.conf, you must manually modify the conf file yourself!"
#else
#	if [[ $PROXY_SUPPORT == "yes" ]]; then
#		echo "$(date) Enabling proxy support"
#		sed -i 's/^#listen-proxy-proto/listen-proxy-proto/' /config/ocserv.conf
#		sed -i 's/^#listen-clear-file/listen-clear-file/' /config/ocserv.conf
#	else
#		sed -i 's/^listen-proxy-proto/#listen-proxy-proto/' /config/ocserv.conf
#		sed -i 's/^listen-clear-file/#listen-clear-file/' /config/ocserv.conf
#	fi
#fi

# Add DNS_SERVERS to ocserv conf
if [[ ${POWER_USER} == "yes" ]]; then
	echo "$(date) [warn] Power user! DNS servers are not being written to ocserv.conf, you must manually modify the conf file yourself!"
else
	sed -i '/^dns =/d' /config/ocserv.conf
	# split comma seperated string into list from NAME_SERVERS env variable
	IFS=',' read -ra name_server_list <<< "${DNS_SERVERS}"
	# process name servers in the list
	for name_server_item in "${name_server_list[@]}"; do
		DNSDUP=$(cat /config/ocserv.conf | grep "dns = ${name_server_item}")
		if [[ -z "$DNSDUP" ]]; then
			# strip whitespace from start and end of lan_network_item
			name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

			echo "$(date) [info] Adding dns = ${name_server_item} to ocserv.conf"
			echo "dns = ${name_server_item}" >> /config/ocserv.conf
		fi
	done
fi

# Process SPLIT_DNS env var
if [[ ! -z "${SPLIT_DNS_DOMAINS}" ]]; then
	if [[ ${POWER_USER} == "yes" ]]; then
		echo "$(date) [warn] Power user! Split-DNS domains are not being written to ocserv.conf, you must manually modify the conf file yourself!"
	else
		sed -i '/^split-dns =/d' /config/ocserv.conf
		# split comma seperated string into list from SPLIT_DNS_DOMAINS env variable
		IFS=',' read -ra split_domain_list <<< "${SPLIT_DNS_DOMAINS}"
		# process name servers in the list
		for split_domain_item in "${split_domain_list[@]}"; do
			DOMDUP=$(cat /config/ocserv.conf | grep "split-dns = ${split_domain_item}")
			if [[ -z "$DOMDUP" ]]; then
				# strip whitespace from start and end of lan_network_item
				split_domain_item=$(echo "${split_domain_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

				echo "$(date) [info] Adding split-dns = ${split_domain_item} to ocserv.conf"
				echo "split-dns = ${split_domain_item}" >> /config/ocserv.conf
			fi
		done
	fi
fi

##### Generate certs if none exist #####
if [ ! -f /config/certs/server-key.pem ] || [ ! -f /config/certs/server-cert.pem ]; then
	# No certs found
	echo "$(date) [info] No certificates were found, creating them from provided or default values"
	
	# Check environment variables
	if [ -z "$CA_CN" ]; then
		CA_CN="VPN CA"
	fi

	if [ -z "$CA_ORG" ]; then
		CA_ORG="OCSERV"
	fi

	if [ -z "$CA_DAYS" ]; then
		CA_DAYS=9999
	fi

	if [ -z "$SRV_CN" ]; then
		SRV_CN="vpn.example.com"
	fi

	if [ -z "$SRV_ORG" ]; then
		SRV_ORG="MyCompany"
	fi

	if [ -z "$SRV_DAYS" ]; then
		SRV_DAYS=9999
	fi

	# Generate certs one
	mkdir /config/certs
	cd /config/certs
	certtool --generate-privkey --outfile ca-key.pem
	cat > ca.tmpl <<-EOCA
	cn = "$CA_CN"
	organization = "$CA_ORG"
	serial = 1
	expiration_days = $CA_DAYS
	ca
	signing_key
	cert_signing_key
	crl_signing_key
	EOCA
	certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca.pem
	certtool --generate-privkey --outfile server-key.pem 
	cat > server.tmpl <<-EOSRV
	cn = "$SRV_CN"
	organization = "$SRV_ORG"
	expiration_days = $SRV_DAYS
	signing_key
	encryption_key
	tls_www_server
	EOSRV
	certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca.pem --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem
else
	echo "$(date) [info] Using existing certificates in /config/certs"
fi


if [ -z "$DEBUGLEVEL" ]; then
	DEBUGLEVEL=1
else
  DEBUGLEVEL=$DEBUGLEVEL
fi

# Open ipv4 ip forward
sysctl -w net.ipv4.ip_forward=1

# Enable NAT forwarding
iptables -t nat -A POSTROUTING -j MASQUERADE
#iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS

# Enable TUN device
mkdir -p /dev/net
mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun

chmod -R 777 /config

# Run OpenConnect Server
exec "$@ -d $DEBUGLEVEL"
