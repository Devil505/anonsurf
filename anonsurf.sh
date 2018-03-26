#!/bin/bash

### BEGIN INIT INFO
# Provides:          anonsurf
# Required-Start:
# Required-Stop:
# Should-Start:
# Default-Start:
# Default-Stop:
# Short-Description: Transparent Proxy through TOR.
### END INIT INFO
#
# Devs:
# Lorenzo 'EclipseSpark' Faletra <eclipse@frozenbox.org>
# Lisetta 'Sheireen' Ferrero <sheireen@frozenbox.org>
# Francesco 'mibofra'/'Eli Aran'/'SimpleSmibs' Bonanno
# <mibofra@ircforce.tk> <mibofra@frozenbox.org>
#
#
# anonsurf is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# You can get a copy of the license at www.gnu.org/licenses
#
# anonsurf is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Parrot Security OS. If not, see <http://www.gnu.org/licenses/>.

export BLUE='\033[1;94m'
export YELLOW='\033[1;93m'
export GREEN='\033[1;92m'
export RED='\033[1;91m'
export RESETCOLOR='\033[5;00m'


# Destinations you don't want routed through Tor
TOR_EXCLUDE="192.168.0.0/16 172.16.0.0/12 10.0.0.0/8"

# The UID Tor runs as
# change it if, starting tor, the command 
# 'ps -e | grep tor' returns a different UID
TOR_UID="tor"

# Tor's TransPort
TOR_PORT="9040"



function notify {
    printf "$YELLOW%s\n$RESETCOLOR" "$1"
}
export notify


function clean_dhcp {
	dhclient -r
	rm -f /var/lib/dhcp/dhclient*
	echo -e -n "$BLUE[$GREEN*$BLUE] DHCP address released"
	notify "DHCP address released"
}


function init {
	echo -e "$BLUE[$GREEN*$BLUE] Killing dangerous applications"
	killall -q chrome dropbox iceweasel skype icedove \
        thunderbird firefox firefox-esr chromium xchat \
        hexchat transmission steam

	echo -e "$BLUE[$GREEN*$BLUE] Cleaning some dangerous cache elements"
	bleachbit -c adobe_reader.cache chromium.cache chromium.current_session \
        chromium.history elinks.history emesene.cache epiphany.cache \
        firefox.url_history flash.cache flash.cookies google_chrome.cache \
        google_chrome.history  links2.history opera.cache opera.search_history \
        opera.url_history &> /dev/null
}



function starti2p {
	echo -e "$BLUE[$GREEN*$BLUE] Starting I2P services"
    sudo systemctl start i2prouter.service || \
        { echo -e "$BLUE[$RED*$BLUE] I2P daemon failed"; exit; }
    while : ; do
        sleep 2
        ! $(systemctl -q is-active i2prouter.service) || break
    done 
	echo -e "$BLUE[$GREEN*$BLUE] Starting firefox at I2P homepage"
    firefox http://127.0.0.1:7657/home >/dev/null &
    echo -e "$BLUE[$GREEN*$BLUE] I2P daemon started"
}

function stopi2p {
	echo -e "$BLUE[$GREEN*$BLUE] Stopping I2P services"
	sudo systemctl stop i2prouter.service 
	echo -e "$BLUE[$GREEN*$BLUE] I2P daemon stopped"
}



function ip {
	MYIP=`curl --silent https://start.parrotsec.org/ip/`
    printf "$YELLOW%s$RESETCOLOR" "$MYIP"
}
export ip


function start {
	# Make sure only root can run this script
	if [ $(id -u) -ne 0 ]; then
		echo -e -e "\n$GREEN[$RED!$GREEN] $RED R U DRUNK??"\
            " This script must be run as root\n" >&2
		exit 1
	fi

	 notify "Starting anonymous mode"

    if ! $(systemctl -q is-active tor.service); then
		echo -e "$BLUE[$RED*$BLUE] Tor is not running!$GREEN"\
            "starting it$BLUE for you" >&2

		echo -e -n "$BLUE[$GREEN*$BLUE] Stopping service nscd$RED"
        $(systemctl -q is-active nscd) && \
            { systemctl stop nscd; echo; } || \
                echo -e "$BLUE (already stopped)"

		echo -e -n "$BLUE[$GREEN*$BLUE] Stopping service systemd-resolved$RED"
        $(systemctl -q is-active systemd-resolved) && \
            { systemctl stop systemd-resolved; echo; } || \
                echo -e "$BLUE (already stopped)"

		echo -e -n "$BLUE[$GREEN*$BLUE] Stopping service dnsmasq$RED"
		$(systemctl -q is-active dnsmasq) && \
            { systemctl stop dnsmasq; echo; } || \
                echo -e "$BLUE (already stopped)"

		killall dnsmasq nscd 2>/dev/null || true
		sleep 2
		killall -9 dnsmasq 2>/dev/null || true

		systemctl start tor
		sleep 5
	fi


	if ! [ -f /etc/iptables/iptables.rules ]; then
		iptables-save > /etc/iptables/iptables.rules
		echo -e " $GREEN*$BLUE Saved iptables rules$RED"
	fi

	iptables -F
	iptables -t nat -F

	cp /etc/resolv.conf /etc/resolv.conf.bak
	touch /etc/resolv.conf
	echo -e "nameserver 127.0.0.1\nnameserver 92.222.97.145\n"\
"nameserver 192.99.85.244" > /etc/resolv.conf
	echo -e "$BLUE[$GREEN*$BLUE] Modified resolv.conf to use Tor and ParrotDNS$RED"

	# disable ipv6
	echo -e "$BLUE[$GREEN*$BLUE] Disable ipv6$RED"
	sysctl -w net.ipv6.conf.all.disable_ipv6=1 1>/dev/null
	sysctl -w net.ipv6.conf.default.disable_ipv6=1 1>/dev/null

	echo -e "$BLUE[$GREEN*$BLUE] Set iptables rules$RED"
	# set iptables nat
	iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -j RETURN

	#set dns redirect
	iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 53
	iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 53
	iptables -t nat -A OUTPUT -p udp -m owner --uid-owner $TOR_UID -m udp --dport 53 -j REDIRECT --to-ports 53

	#resolve .onion domains mapping 10.192.0.0/10 address space
	iptables -t nat -A OUTPUT -p tcp -d 10.192.0.0/10 -j REDIRECT --to-ports $TOR_PORT
	iptables -t nat -A OUTPUT -p udp -d 10.192.0.0/10 -j REDIRECT --to-ports $TOR_PORT

	#exclude local addresses
	for NET in $TOR_EXCLUDE 127.0.0.0/9 127.128.0.0/10; do
		iptables -t nat -A OUTPUT -d $NET -j RETURN
		iptables -A OUTPUT -d "$NET" -j ACCEPT
	done

	#redirect all other output through TOR
	iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TOR_PORT
	iptables -t nat -A OUTPUT -p udp -j REDIRECT --to-ports $TOR_PORT
	iptables -t nat -A OUTPUT -p icmp -j REDIRECT --to-ports $TOR_PORT

	#accept already established connections
	iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

	#allow only tor output
	iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
	iptables -A OUTPUT -j REJECT

	echo -e "$BLUE[$GREEN*$BLUE] All traffic was redirected throught Tor\n"
	# echo -e "$GREEN[$BLUE i$GREEN ]$BLUE You are under AnonSurf tunnel\n"
    notify "Global Anonymous Proxy Activated - $(ip)"
    notify "Dance like no one's watching. Encrypt like everyone is :)"
}





function stop {
	# Make sure only root can run our script
	if [ $(id -u) -ne 0 ]; then
		echo -e "\n$GREEN[$RED!$GREEN] $RED R U DRUNK?? "\
            "This script must be run as root\n" >&2
		exit 1
	fi
	notify "Stopping anonymous mode"

	iptables -F
	iptables -t nat -F
	echo -e "$BLUE[$GREEN*$BLUE] Deleted all iptables rules$RED"

	if [ -f /etc/iptables/iptables.rules ]; then
		iptables-restore < /etc/iptables/iptables.rules
		# rm /etc/network/iptables.rules
		echo -e "$BLUE[$GREEN*$BLUE] Iptables rules restored$RED"
	fi
	echo -e "$BLUE[$GREEN*$BLUE] Restore DNS service$RED"
	if [ -e /etc/resolv.conf.bak ]; then
		rm /etc/resolv.conf
		cp /etc/resolv.conf.bak /etc/resolv.conf
	fi

	# re-enable ipv6
	echo -e "$BLUE[$GREEN*$BLUE] Renable ipv6$RED"
	sysctl -w net.ipv6.conf.all.disable_ipv6=0 1>/dev/null
	sysctl -w net.ipv6.conf.default.disable_ipv6=0 1>/dev/null

	systemctl stop tor
	sleep 2
	killall tor 2>/dev/null || true

	echo -e -n "$BLUE[$GREEN*$BLUE] Restarting services\n$RED"
	(! $(systemctl -q is-active systemd-resolved) && \
        $(systemctl -q is-enabled systemd-resolved)) && \
        systemctl start systemd-resolved
	(! $(systemctl -q is-active dnsmasq) && \
        $(systemctl -q is-enabled dnsmasq)) && systemctl start dnsmasq
	(! $(systemctl -q is-active nscd) && \
        $(systemctl -q is-enabled nscd)) && systemctl start nscd
	echo -e "$BLUE[$GREEN!$BLUE] It is safe to not worry for dnsmasq and"\
        "nscd start errors\n    if they are not installed or started already."
	sleep 1

	echo -e "$BLUE[$GREEN*$BLUE] Anonymous mode stopped\n$RESETCOLOR"
	notify "Global Anonymous Proxy Closed - Stop dancing :(" 
}

function change {
	exitnode-selector
	sleep 10
	echo -e " $GREEN*$BLUE Tor daemon reloaded and forced to change nodes\n"
	notify "Identity changed - let's dance again!"
	sleep 1
}

function status {
    $(systemctl -q is-active tor.service) && \
        notify "AnonSurf is Active - Keep dancing" || \
        notify "AnonSurf is not active - Everyone is watching"
}



case "$1" in
	start)
        echo -e $BLUE
        read -n 1 -rp $'Do you want anonsurf to kill dangerous applications\nand clean some application caches (Y/n) : '
        [[ $REPLY  =~ ^([Yy]$|$) ]] && init
        echo
		start
	;;
	stop)
        echo -e $BLUE
        read -n 1 -rp $'Do you want anonsurf to kill dangerous applications\nand clean some application caches (Y/n) : '
        [[ $REPLY  =~ ^([Yy]$|$) ]] && init
        echo
		stop
	;;
	change)
		change
	;;
	status)
		status
	;;
	myip)
		ip
	;;
	ip)
		ip
	;;
	starti2p)
		starti2p
	;;
	stopi2p)
		stopi2p
	;;
	restart)
		$0 stop
		sleep 1
		$0 start
	;;
   *)
echo -e "
Parrot AnonSurf Module (v 2.5)
	Developed by Lorenzo \"Palinuro\" Faletra <palinuro@parrotsec.org>
		     Lisetta \"Sheireen\" Ferrero <sheireen@parrotsec.org>
		     Francesco \"Mibofra\" Bonanno <mibofra@parrotsec.org>
		and a huge amount of Caffeine + some GNU/GPL v3 stuff
	Usage:
	$RED┌──[$GREEN$USER$YELLOW@$BLUE`hostname`$RED]─[$GREEN$PWD$RED]
	$RED└──╼ \$$GREEN"" anonsurf $RED{$GREEN"\
        "start$RED|$GREEN""stop$RED|$GREEN""restart$RED|$GREEN"\
        "change$RED""$RED|$GREEN""status$RED""}

	$RED start$BLUE -$GREEN Start system-wide TOR tunnel	
	$RED stop$BLUE -$GREEN Stop anonsurf and return to clearnet
	$RED restart$BLUE -$GREEN Combines \"stop\" and \"start\" options
	$RED change$BLUE -$GREEN Restart TOR to change identity
	$RED status$BLUE -$GREEN Check if AnonSurf is working properly
	$RED myip$BLUE -$GREEN Check your ip and verify your tor connection

	----[ I2P related features ]----
	$RED starti2p$BLUE -$GREEN Start i2p services
	$RED stopi2p$BLUE -$GREEN Stop i2p services
$RESETCOLOR
Dance like no one's watching. Encrypt like everyone is.
" >&2

exit 1
;;
esac

echo -e $RESETCOLOR
exit 0

