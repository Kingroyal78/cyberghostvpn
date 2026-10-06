ARG DEBIAN_VERSION=13
ARG CYBERGHOST_VERSION=1.3.4
#CyberGhost only ships Ubuntu builds. The CLI is a self-contained PyInstaller binary, so it runs on Debian as-is
ARG CYBERGHOST_BUILD=ubuntu-20.04

#Unpack the cached CyberGhost CLI in a throwaway stage so unzip doesn't end up in the final image
FROM debian:${DEBIAN_VERSION}-slim AS cyberghost
ARG CYBERGHOST_VERSION
ARG CYBERGHOST_BUILD

RUN apt-get update && \
	apt-get install -y --no-install-recommends unzip && \
	rm -rf /var/lib/apt/lists/*

#Original download URL [returns 403 as of 2026-10, kept for reference]:
#https://download.cyberghostvpn.com/linux/cyberghostvpn-$CYBERGHOST_BUILD-$CYBERGHOST_VERSION.zip
COPY ver/cyberghostvpn-${CYBERGHOST_BUILD}-${CYBERGHOST_VERSION}.zip /tmp/cyberghostvpn.zip
RUN unzip -q /tmp/cyberghostvpn.zip -d /tmp && \
	mv /tmp/cyberghostvpn-${CYBERGHOST_BUILD}-${CYBERGHOST_VERSION}/cyberghost /opt/cyberghost && \
	chmod -R 755 /opt/cyberghost


FROM debian:${DEBIAN_VERSION}-slim
ARG DEBIAN_VERSION
ARG CYBERGHOST_VERSION
ARG buildtime_script_version

LABEL MAINTAINER="Tyler McPhee"
LABEL CREATOR="Tyler McPhee"
LABEL GITHUB="https://github.com/tmcphee/cyberghostvpn"
LABEL DOCKER="https://hub.docker.com/r/tmcphee/cyberghostvpn"

ENV cyberghost_version=${CYBERGHOST_VERSION} \
	linux_version=${DEBIAN_VERSION} \
	script_version=${buildtime_script_version}

ARG DEBIAN_FRONTEND=noninteractive

#Everything the CyberGhost installer would fetch [openvpn, wireguard, resolvconf] plus what start.sh needs.
#openresolv is required: wg-quick pipes the "DNS =" line of the CyberGhost config into resolvconf
RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		expect \
		iproute2 \
		iptables \
		iputils-ping \
		openresolv \
		openvpn \
		procps \
		squid \
		sudo \
		systemctl \
		tzdata \
		ufw \
		wireguard-tools && \
	rm -rf /var/lib/apt/lists/*

#Use the legacy iptables backend like the old Ubuntu 20.04 image did. Some NAS kernels lack nf_tables
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
	update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

#The systemctl replacement predates Python 3.12 and prints SyntaxWarnings on every call. Silence them
RUN sed -i '1s|^#! */usr/bin/python3$|#! /usr/bin/python3 -Wignore::SyntaxWarning|' /usr/bin/systemctl

#Install CyberGhost CLI. Same result as the bundled install.sh, without its dead WireGuard PPA and apt-key steps
COPY --from=cyberghost /opt/cyberghost /usr/local/cyberghost
RUN ln -sf /usr/local/cyberghost/cyberghostvpn /usr/bin/cyberghostvpn

#Setup HTTP Proxy. Allow all connections
RUN sed -i 's/http_access allow localhost/http_access allow all/g' /etc/squid/squid.conf && \
	sed -i 's/http_access deny all/#http_access deny all/g' /etc/squid/squid.conf

#Disable IPV6 on ufw
RUN sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw

#start.sh writes .FIREWALL.cg relative to the working directory and checks for /.FIREWALL.cg
WORKDIR /
COPY start.sh auth.sh /
#Strip CRLF in case the repo was checked out on Windows
RUN sed -i 's/\r$//' /start.sh /auth.sh && \
	chmod +x /start.sh /auth.sh

CMD ["bash", "/start.sh"]
