#!/bin/sh
##############################################################################
# mkcertchlg.nginxconf.sh
#   Let's Encrypt certificate challeng conf maker.
#   Author: T.Hayashi (hayashi@rookie-inc.com)
#   License: BSD 2 clause
##############################################################################
### Initial value.
__VERSION="0.1"
__TAB=$'\t'
__PROCDATE=$(date "+%Y%m%d.%H%M%S")

__COMMAND=$(basename ${0})
__DBG=0         # Debug Information
__TEST=0        # Dry Run
__HOME=$(pwd)   # Certificate home directory.
__CONF="${__HOME}/mkcertchlg.nginxconf.conf"  # configuration file.
__DUSER=""      # Distribute username for ssh.

__LISTEN="80"
__ACCESSLOG="/var/log/nginx/acme-challenge.access.log"
__ERRORLOG="/var/log/nginx/acme-challenge.error.log error"

__LOG="/dev/null"
__TMP=$(mktemp -d ${__COMMAND}.XXXXXXXX)

trap "rm -rf ${__TMP}" EXIT

##### functions definition.
cu_debug() { # Debug output to stderr. ${1}:Messages / ${2}:Flag(Exit)
  echo "DBG:${1}" >&2
  echo "DBG:${1}" >> ${__LOG}
  [ -n "${2}" ] && exit 1
}

cu_usage() { # Usage Message. force exit.
cat <<_EOT_
${__COMMAND} ver. ${__VERSION}
Usage: ${__COMMAND} [-dt] [-C config] [-T template] [-D nginx conf] [-W webroot] domain
  domain: target domain
  -d : DEBUG mode. Verbose message.
  -t : test mode. Display only
	-C config: configuration file (Default: ./mkcertchlg.nginxconf.conf)
  -T template: template file (Default: ./template/certchlg.nginx.conf)
  -D nginx conf: Conf Destination Dir (Default: /usr/local/etc/nginx/site)
  -W webroot: WebRoot Dir (default: ./htdocs)
_EOT_
  exit 1
}

##### Main #####

### Get options.
while getopts "dtC:D:T:W:" __FLAG__; do
  case "${__FLAG__}" in
    d)  # DEBUG Mode
      __DBG=1
      ;;
    t)  # TEST Mode
      __TEST=1
      ;;
    C)	# config file
      __CONF=${OPTARG}
      ;;
    D)	# Destination config file
      __DESTDIR=${OPTARG}
      ;;
    W)	# WebRoot Directory
      __WEBROOT=${OPTARG}
      ;;
    *)
      cu_usage
    ;;
  esac
done

### include config.
if [ -e ${__CONF} ]; then
  . ${__CONF}
  [ ${?} -ne 0 ] && echo "Error: Configuration file ${__CONF} is somthing wrong. check it." && exit 1
fi

shift $(( ${OPTIND} - 1 ))
__DOMAIN="${1}"

if [ -z "${__DOMAIN}" ]; then
  echo "Error: ${__COMMAND} Rquirement Domain."
  cu_usage
fi

### Set default value.
: ${__WEBROOT:="${__HOME}/htdocs"}        # ACME WebRoot Directory.
: ${__CONF:="${__HOME}/mkcertchlg.nginxconf.conf"}  # configuration file.
: ${__TEMPLATE:="${__HOME}/template/certchlg.nginx.conf.template"}  # template file.
: ${__DESTDIR:="/usr/local/etc/nginx/conf.d"} # Destination Dir.
: ${__NGINXCONFFILE:=".acme.challeng.conf"} # Destination file.
__NGINXCONF="${__DESTDIR}/${__DOMAIN}${__NGINXCONFFILE}"

if [ "${__DBG}" -ne 0 ]; then
  cu_debug "Test      = ${__TEST}"
  cu_debug "TMP       = ${__TMP}"
  cu_debug "conf      = ${__CONF}"
  cu_debug "dist user = ${__DUSER}"
  cu_debug "Webroot   = ${__WEBROOT}"
  cu_debug "Dest Dir  = ${__DESTDIR}"
  cu_debug "template  = ${__TEMPLATE}"
  cu_debug "Domain    = ${__DOMAIN}"
  cu_debug "LISTEN    = ${__LISTEN}"
  cu_debug "ACCESSLOG = ${__ACCESSLOG}"
  cu_debug "ERRORLOG  = ${__ERRORLOG}"
  cu_debug "NginxConf = ${__NGINXCONF}"
fi

if [ -e ${__TEMPLATE} ]; then
  cp ${__TEMPLATE} ${__TMP}
  __PROCFILE="${__TMP}/$(basename ${__TEMPLATE})"
else
  echo "Error: Template file ${__TEMPLATE} is noy found." && exit 1
fi
if [ ! -d ${__DESTDIR} ]; then
  echo "Error: Detination dir ${__DESTDIR} is noy found." && exit 1
fi

__ACCESSLOG=$( echo "${__ACCESSLOG}" | sed -e "s%/%\\\\/%g")
__ERRORLOG=$( echo "${__ERRORLOG}" | sed -e "s%/%\\\\/%g")
__WEBROOT=$( echo "${__WEBROOT}" | sed -e "s%/%\\\\/%g")

sed -i "" -e "s/__LISTEN__/${__LISTEN}/g" ${__PROCFILE}
sed -i "" -e "s/__DOMAIN__/${__DOMAIN}/g" ${__PROCFILE}
sed -i "" -e "s/__ACCESSLOG__/${__ACCESSLOG}/g" ${__PROCFILE}
sed -i "" -e "s/__ERRORLOG__/${__ERRORLOG}/g" ${__PROCFILE}
sed -i "" -e "s/__WEBROOT__/${__WEBROOT}/g" ${__PROCFILE}

if [ "${__TEST}" -ne 0 ]; then
  cat "${__PROCFILE}"
else
  # backup nginx config
  if [ -e ${__NGINXCONF} ]; then
    sudo mv "${__NGINXCONF}" "${__NGINXCONF}.${__PROCDATE}~"
    [ ${__DBG} -ne 0 ] && ls -la "${__NGINXCONF}.${__PROCDATE}~"
  fi
  sudo cp ${__PROCFILE} ${__NGINXCONF}
  if [ "${__DBG}" -ne 0 ]; then
    cat "${__NGINXCONF}"
  fi
  sudo service nginx reload 2>&1


fi

