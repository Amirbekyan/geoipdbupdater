#!/bin/bash

# Error Codes
# 4	No files downloaded
# 3	Component not found
# 2	No lisence key set in /etc/geoipdbupdater.conf

errmsg() {
	case $1 in
		conf)	echo "No config file found"
			exit 3;;
		usher)	echo "No usher file found"
			exit 3;;
		key)	echo "No KEY set in /etc/geoipdbupdater.conf!"
			exit 2;;
		ver)	echo "No GEOIPVER set in /etc/geoipdbupdater.conf!"
			exit 2;;
		nofile)	echo "No files downloaded!"
			exit 0;;
	esac
}

[ -r /etc/geoipdbupdater.conf ] || errmsg conf
# [ -r /usr/local/lib/geoipdbupdater/usher ] || errmsg usher

source /etc/geoipdbupdater.conf
# source /usr/local/lib/geoipdbupdater/usher

[ ${KEY} ] || errmsg key
[ ${GEOIPVER} ] || errmsg ver

BINDIR=/usr/bin
LOGDIR=/var/log
LOGFILE=geoipdbupdater_version.log
[ -r $LOGDIR/$LOGFILE ] || echo $(date)_INIT_LOG_$(date -d "-8 day" +%Y%m%d) > $LOGDIR/$LOGFILE
SHAREDIR=${1:-/usr/share/geoipdbupdater}
[ -d $SHAREDIR ] || mkdir -p $SHAREDIR
[ -d /usr/share/GeoIP ] || mkdir -p /usr/share/GeoIP

FILES_DOWNLOADED=0
DATE=$(date +%Y%m%d)
PREV_VERSION=$(tail -n 1 $LOGDIR/$LOGFILE | awk -F _ {'print $4'})
NEW_VERSION=$(date -d "$PREV_VERSION 1 day" +%Y%m%d)

set_url() {
	URL="https://download.maxmind.com/app/geoip_download?edition_id=${EDITION_ID}&date=${VERSION}&suffix=tar.gz&license_key=${KEY}"
}

case $GEOIPVER in
	legacy)
		TYPES=(GEOIP_COUNTRY GEOIP_CITY)
		DBFILEFORMATS=("dat");;
	geoip2)
		TYPES=(GEOIP2_COUNTRY GEOIP2_CITY)
		DBFILEFORMATS=("mmdb");;
	geolite2)
		TYPES=(GEOLITE2_COUNTRY GEOLITE2_CITY GEOLITE2_ASN)
		DBFILEFORMATS=("mmdb");;		
	all)
		TYPES=(GEOIP_COUNTRY GEOIP_CITY GEOIP2_COUNTRY GEOIP2_CITY GEOLITE2_COUNTRY GEOLITE2_CITY GEOLITE2_ASN)
		DBFILEFORMATS=("dat" "mmdb");;
esac

set_edition() {
	case $TYPE in
		GEOIP_COUNTRY)		EDITION_ID="106";;
		GEOIP_CITY)			EDITION_ID="133";;
		GEOIP2_COUNTRY)		EDITION_ID="GeoIP2-Country";;
		GEOIP2_CITY)		EDITION_ID="GeoIP2-City";;
		GEOLITE2_COUNTRY)	EDITION_ID="GeoLite2-Country";;
		GEOLITE2_CITY)	 	EDITION_ID="GeoLite2-City";;
		GEOLITE2_ASN)	 	EDITION_ID="GeoLite2-ASN"
	esac
}

for ff in ${!DBFILEFORMATS[@]}; do
	if [ $ff -eq 0 ]; then
		REGEX=".*\.("
	else
		REGEX="${REGEX}|"
	fi
	REGEX="${REGEX}${DBFILEFORMATS[$ff]}"
	[ ${DBFILEFORMATS[$ff+1]} ] || REGEX="${REGEX})"
done

file_downloader(){
	for ((VERSION=$NEW_VERSION; VERSION<=$DATE; VERSION=$(date -d "$VERSION 1 day" +%Y%m%d))); do
		for TYPE in ${TYPES[@]}; do
			set_edition
			set_url
			if [[ $(curl -s -I "$URL" | head -n 1) =~ 200 ]]; then
				wget "$URL" -O $SHAREDIR/${TYPE,,}.tar.gz
				if [ $? != 0 ]; then
					continue
				fi
				echo "$(date)_${TYPE}_$VERSION" >> $LOGDIR/$LOGFILE
				FILES_DOWNLOADED=$[$FILES_DOWNLOADED+1]
			fi
		done
	done
}

file_manager() {
	if [ $FILES_DOWNLOADED -gt 0 ]; then
		for ARCHIVE in $SHAREDIR/*.tar.gz; do
			tar -xzf $ARCHIVE -C $SHAREDIR
		done
	
		FILES=($(find $SHAREDIR/ -mindepth 2 -regextype posix-extended -regex ${REGEX}))

		for file in ${FILES[@]}; do
			case $(basename ${file}) in
				GeoIP2-Country.mmdb|GeoIP2-City.mmdb|GeoIPCity.dat)	mv ${file} ${SHAREDIR}/$(basename ${file})
											SYMLINKS=(${SYMLINKS} $(basename ${file}));;
				GeoIP-106*)							mv ${file} ${SHAREDIR}/GeoIP.dat
											SYMLINKS=(${SYMLINKS} GeoIP.dat);;
			esac
		done

		find $SHAREDIR/ -maxdepth 1 -not -name "GeoIPCity.dat" -not -name "GeoIP.dat" -not -name "GeoIP2-Country.mmdb" -not -name "GeoIP2-City.mmdb" -not -path "$SHAREDIR/" -exec rm -rf {} \;
	
		chown -R root:root $SHAREDIR

		for sl in ${SYMLINKS[@]}; do
			[ -h /usr/share/GeoIP/${sl} ] && unlink /usr/share/GeoIP/${sl}
		done

		/bin/cp -a $SHAREDIR/GeoIP* /usr/share/GeoIP/
	else
		errmsg nofile
	fi
}

file_downloader
file_manager && exit 0