#!/bin/bash
set -e
cat << 'BANNER'

_____   __    ______________            ______
___  | / /______  /__  ____/_____ _________  /______
__   |/ /_  _ \  __/  /    _  __ `/  ___/_  __ \  _ \
_  /|  / /  __/ /_ / /___  / /_/ // /__ _  / / /  __/
/_/ |_/  \___/\__/ \____/  \__,_/ \___/ /_/ /_/\___/

BANNER

# Provide Defaults
CACHE_MEM_SIZE="${CACHE_MEM_SIZE:-"500m"}" # Default to 500MB memory (per service/server)
CACHE_DISK_SIZE="${CACHE_DISK_SIZE:-"1000000m"}" # Default to 1TB disk-space
CACHE_MAX_AGE="${CACHE_MAX_AGE:-"3650d"}" # Default to 10 years
LOGFILE_RETENTION="${LOGFILE_RETENTION:="1461d"}" # Default to 4 years
NGINX_WORKER_PROCESSES="${NGINX_WORKER_PROCESSES:-"16"}" # Default to 16 workers
INACTIVE_TIME="${INACTIVE_TIME:-"365d"}" # Default to 1 year
UPSTREAM_DNS="${UPSTREAM_DNS:-"$(sed -n "s/^nameserver //p" /etc/resolv.conf)"}" # Default to the system nameservers

# Static Entries
CACHE_DOMAINS_REPO="https://raw.githubusercontent.com/uklans/cache-domains/master/"
SNI_CONF="/etc/sniproxy.conf"
NGINX_CONF="/etc/nginx/nginx.conf"
RESOLVER_CONF="/etc/nginx/sites-available/conf.d/resolver.conf"
DNSRESOLV="/etc/resolv.conf"
SERVICES_DIR="/etc/nginx/sites-available/"
MAPS_DIR="/etc/nginx/conf.d/maps.d/"
PROXYCACHEPATH_DIR="/etc/nginx/conf.d/proxy_cache_path.d/"
CACHE_PATH="/data/cache"
LOGS_PATH="/data/logs"


# Helpful function(s)
fnSplitStrings () { # Removes comments, splits into lines from comma/space delimited strings, and removes any blank lines.
 echo "$1" |sed "s/[, ]*#.*$//;s/[, ]/\n/g" |sed "/^$/d"
}
fnReadEnvironmentVariable () { # Given a string, finds a matching environment variable value using a case-insensitive search.
 printenv "$(env |sed -n "s/^\($1\)=.*$/\1/Ip"|head -n1)"
}

# DNS Nameserver Setup
DNS_NAMESERVERS="" # Used for named.conf.options and resolver.conf 
setupDNS () { # setupDNS "Comma-Separated-IPs"
 if ! [ -z "$1" ];then # String containing DNS entries, comma/space delimited.
  cat /dev/null > "${DNSRESOLV}"
  fnSplitStrings "$1" |while read DNS_IP;do
   echo "+ Adding nameserver: ${DNS_IP}"
   echo "nameserver ${DNS_IP}" >> "${DNSRESOLV}"
  done
  DNS_NAMESERVERS="$(fnSplitStrings "$1" |paste -sd ' ' - )" # Space delimited DNS IPs for sniproxy.conf and resolver.conf
  echo
 fi
}

# nginx Config Setup
addServiceComment () { # addServiceComment "Service Name" "Comment String"
 ServiceName="$1" # Name of the given service.
 Comment="$2" # String
 echo "${Comment}" |sed "s/^/# /" >> "${SERVICES_DIR%/}/${ServiceName}.conf"
 echo "${Comment}" |sed "s/^/# /" >> "${MAPS_DIR%/}/${ServiceName}.conf"
}
addService () { # addService "Service Name" "Domain Names"
 ServiceName="$1" # Name of the given service.
 Domains="$2" # String containing domain name entries, comma/space delimited.

 if [ -z "${ServiceName}" ]||[ -z "${Domains}" ];then # All fields are required.
  echo "# Error adding service \"${ServiceName}\".  All arguments are required." >&2
  return
 fi
 echo "+ Mapping service \"${ServiceName}\"."

 Listen_Options=""
 if [ "${ServiceName}" == "_default_" ];then # Default service for unmatched domains
  Conf_File="/etc/nginx/conf.d/default.conf"
  Server_Names="# Matches all unmatched domains"

  # Add "default_server" to the listen directive
  Listen_Options="default_server reuseport"

  # Remove the nginx-provided "default.conf" file.
  rm -f /etc/nginx/conf.d/default.conf
 else
  Conf_File="${SERVICES_DIR%/}/${ServiceName}.conf"
  Domain_Names="$(fnSplitStrings "${Domains}" |sed "s/^\*\.//;s/^/\*\./" |sort -u |paste -sd ' ' - )" # Space delimited domain names
  Server_Names="server_name ${Domain_Names};"

  # Add service maps
  fnSplitStrings "${Domains}" |sed "s/^\*\.//;s/^/\*\./;s/^/    /;s/$/ ${ServiceName};/" |sort -u >> "${MAPS_DIR%/}/${ServiceName}.conf"
 fi

 # Setup and create the service-specific cache directory
 Service_Cache_Path="${CACHE_PATH%/}/${ServiceName}"
 mkdir -p "${Service_Cache_Path}"


 # Create/append ${ServiceName}.conf file
 cat << EOF >> "${Conf_File}"
server {
  listen 80 ${Listen_Options};
  ${Server_Names}

  access_log ${LOGS_PATH%/}/cache.log cachelog;
  error_log ${LOGS_PATH%/}/error.log;

  include /etc/nginx/sites-available/conf.d/resolver.conf;

  # Cache Location
  proxy_cache ${ServiceName};

  location / {
    include /etc/nginx/sites-available/root.d/*.conf;
  }

  include /etc/nginx/sites-available/conf.d/fix_lol_updater.conf;
}
EOF

 # Add proxy_cache_path Entries
 cat << EOF >> "${PROXYCACHEPATH_DIR%/}/${ServiceName}.conf"
proxy_cache_path ${Service_Cache_Path} levels=2:2 keys_zone=${ServiceName}:${CACHE_MEM_SIZE} inactive=${INACTIVE_TIME} max_size=${CACHE_DISK_SIZE} loader_files=1000 loader_sleep=50ms loader_threshold=300ms use_temp_path=off;
EOF

}



# Startup Checks
if [ -z "${UPSTREAM_DNS}" ];then
 echo "UPSTREAM_DNS environment variable is not set.  This is required to be set."
 exit 1
fi

# Setup DNS Nameservers
setupDNS "${UPSTREAM_DNS}"

# Create directories
mkdir -p "${SERVICES_DIR}" "${MAPS_DIR}" "${PROXYCACHEPATH_DIR}" "${LOGS_PATH}"

# Cleanup destination folders, just in case script is restarted.
rm -f "${SERVICES_DIR%/}/*.conf" "${MAPS_DIR%/}/*.conf" "${PROXYCACHEPATH_DIR%/}/*.conf"

# Apply the CACHE_MAX_AGE environment variable
sed -i "s/CACHE_MAX_AGE/${CACHE_MAX_AGE}/" /etc/nginx/sites-available/root.d/20_cache.conf

# Set the worker_processes
echo "worker_processes ${NGINX_WORKER_PROCESSES};" > /etc/nginx/workers.conf

# DNS Nameservers (for sniproxy.conf)
NAMESERVERS="# No DNS forwarders"
if ! [ -z "${DNS_FORWARDERS}" ];then
 NAMESERVERS="nameserver ${DNS_NAMESERVERS};"
fi

# Generate sniproxy.conf file
cat << EOF > "${SNI_CONF}"
user nobody

pidfile /var/run/sniproxy.pid

resolver {
	${NAMESERVERS}
	mode ipv4_only
}

access_log {
	filename ${LOGS_PATH%/}/sniproxy.log
	#priority notice
}

error_log {
	filename ${LOGS_PATH%/}/error.log
}

listener 0.0.0.0:443 {
	protocol tls
}

table {
	.* *:443
}
EOF

# Generate resolver.conf file
cat << EOF > "${RESOLVER_CONF}"
  resolver ${DNS_NAMESERVERS} ipv6=off;
EOF

# Check permissions on /data folder...
echo -n "* Checking permissions (This may take a long time if the permissions are incorrect on large caches)..."
find /data \! -user nginx -exec chown nginx:nginx '{}' +
echo "  Done."


# Add a fallback default cache service in case a domain entry does not match
addService "_default_" "*"



## UK-LANs Cache-Domain Lists
echo "* Bootstrapping DNS from ${CACHE_DOMAINS_REPO}"
curl -s "${CACHE_DOMAINS_REPO%/}/cache_domains.json" |jq -c '.cache_domains[]' |while read obj;do
 Service_Name=`echo "${obj}"|jq -r '.name'`
 Service_Desc=`echo "${obj}"|jq -r '.description'`
 if (! (env |grep -iq "^DISABLE_${Service_Name^^}=true") && [ -z "${ONLYCACHE}" ])||[[ " ${ONLYCACHE^^} " == *" ${Service_Name^^} "* ]];then # Continue only if DISABLE_${Service} is not true and ONLYCACHE is empty.  Or continue if service is provided in the ONLYCACHE variable.  (Note that a service in ONLYCACHE will ignore the DISABLE_${Service} variable.)
  addServiceComment "${Service_Name}" "${Service_Name}"
  if ! [ -z "${Service_Desc}" ];then
   addServiceComment "${Service_Name}" "${Service_Desc}"
  fi
  echo "${obj}" |jq -r '.domain_files[]' |while read domain_file;do
   addServiceComment "${Service_Name}" "(${domain_file})"
   Service_Domains="$(curl -s "${CACHE_DOMAINS_REPO%/}/${domain_file}")"
   addService "${Service_Name}" "${Service_Domains}"
  done
 fi
done


## Custom Domain Lists
if (env |grep -iq "^CUSTOMCACHE=") && ! [ -z "${CUSTOMCACHE}" ];then
 echo "* Adding custom services..."
 for Service_Name in ${CUSTOMCACHE};do
  Service_Source="$(fnReadEnvironmentVariable "${Service_Name^^}CACHE")"
  addServiceComment "${Service_Name}" "${Service_Name}"
  addService "${Service_Name}" "${Service_Source}"
 done
fi



# Enable all configurations found in sites-available...
mkdir -p /etc/nginx/sites-enabled
for conf in /etc/nginx/sites-available/*.conf ;do
 ln -s "${conf}" /etc/nginx/sites-enabled/
done

# Test the nginx configuration...
echo "* Checking nginx configuration"
if ! /usr/sbin/nginx -t ;then
 echo "# Problem with nginx configuration" >&2
 exit 1
fi

# Execute and display logs
echo "* Running SNIProxy and nginx w/logging"
touch ${LOGS_PATH%/}/cache.log ${LOGS_PATH%/}/sniproxy.log ${LOGS_PATH%/}/error.log
tail -F ${LOGS_PATH%/}/cache.log ${LOGS_PATH%/}/sniproxy.log ${LOGS_PATH%/}/error.log &
/usr/sbin/sniproxy -c "${SNI_CONF}"
/usr/sbin/nginx -g "daemon off;" -c "${NGINX_CONF}"

