#!/bin/sh
##############################################################################
# mkcertchlg.nginxconf.sh
#   Let's Encrypt certificate challeng conf maker.
#   Author: T.Hayashi (hayashi@rookie-inc.com)
#   License: BSD 2 clause
#
#   Test: FreeBSD only
#
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

can_connect(){
  if [ -z "${1}" ]; then
    echo >&2 "Error: can_connect: require sudo user name."
    echo "1"
    return
  fi
  if [ -z "${2}" ]; then
    echo >&2 "Error: can_connect: require hostname or IP address"
    echo "1"
    return
  fi
  sudo  -u ${1} ssh -q -T                                                     \
        -o "PasswordAuthentication no"                                        \
        -o "StrictHostKeyChecking no" ${2} ":"                                &&
        echo "0" || echo "1"
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
shift $(( ${OPTIND} - 1 ))
__DOMAIN="${1}"

### include config.
if [ -e ${__CONF} ]; then
  . ${__CONF}
  [ ${?} -ne 0 ] && echo "Error: Configuration file ${__CONF} is somthing wrong. check it." && exit 1
fi

### Set default value.
: ${__WEBROOT:="${__HOME}/htdocs"}              # ACME WebRoot Directory.
: ${__CONF:="${__HOME}/mkcertchlg.nginxconf.conf"}  # configuration file.
: ${__TEMPLATE_C:="${__HOME}/template/certchlg.nginx.conf.template"}  # local template file.
: ${__TEMPLATE_R:="${__HOME}/template/certredir.nginx.conf.template"} # remote template file.
: ${__DESTDIR:="/usr/local/etc/nginx/conf.d"}    # local Destination Dir.
: ${__TGTDIR:="/usr/local/etc/nginx/conf.d"}     # remote Destination Dir.
: ${__NGINXCONF_C_FILE:=".acme.challeng.conf"}  # local Destination file.
: ${__NGINXCONF_R_FILE:=".acme.proxy.conf"}     # remote Destination file.
: ${__DUSER:=$(id -u -n)}   # use ssh
__NGINXCONF_C="${__DESTDIR}/${__DOMAIN}${__NGINXCONF_C_FILE}"
__NGINXCONF_R="${__TGTDIR}/${__DOMAIN}${__NGINXCONF_R_FILE}"

if [ "${__DBG}" -ne 0 ]; then
  cu_debug "Test            = ${__TEST}"
  cu_debug "TMP local       = ${__TMP}"
  cu_debug "conf            = ${__CONF}"
  cu_debug "Webroot         = ${__WEBROOT}"
  cu_debug "local conf Dir  = ${__DESTDIR}"
  cu_debug "template local  = ${__TEMPLATE_C}"
  cu_debug "Domain          = ${__DOMAIN}"
  cu_debug "LISTEN          = ${__LISTEN}"
  cu_debug "ACCESSLOG       = ${__ACCESSLOG}"
  cu_debug "ERRORLOG        = ${__ERRORLOG}"
  cu_debug "NginxConf local = ${__NGINXCONF_C}"
  cu_debug "Remote          = ${__TARGET}"
  cu_debug "ssh user        = ${__DUSER}"
  cu_debug "template Remote = ${__TEMPLATE_R}"
  cu_debug "Remote conf Dir = ${__TGTDIR}"
  cu_debug "LISTEN remote   = ${__TGTLISTEN}"
  cu_debug "PROXYPASS remote= ${__TGTPRX}"
fi

### check Options,Args and optional settings
# check domain
if [ -z "${__DOMAIN}" ]; then
  echo "Error: ${__COMMAND} Rquirement Domain."
  cu_usage
fi

# check cert challenge template
if [ -e ${__TEMPLATE_C} ]; then
  cp ${__TEMPLATE_C} ${__TMP}
  __PROCFILE_C="${__TMP}/$(basename ${__TEMPLATE_C})"
else
  echo "Error: Template file ${__TEMPLATE_C} is noy found." && exit 1
fi
# check destination directory
if [ ! -d ${__DESTDIR} ]; then
  echo "Error: Detination dir ${__DESTDIR} is noy found." && exit 1
fi

# check cert redirect template
if [ -e ${__TEMPLATE_R} ]; then
  cp ${__TEMPLATE_R} ${__TMP}
  __PROCFILE_R="${__TMP}/$(basename ${__TEMPLATE_R})"
else
  echo "Error: Template file ${__TEMPLATE_R} is noy found." && exit 1
fi

# check ssh connectable
if [ $( can_connect ${__DUSER} ${__TARGET} ) != 0  ]; then
    echo "Error: ${__TARGET} can't connect."
    exit 1
fi

# escape path delimiter
__ACCESSLOG=$( echo "${__ACCESSLOG}" | sed -e "s%/%\\\\/%g")
__ERRORLOG=$( echo "${__ERRORLOG}" | sed -e "s%/%\\\\/%g")
__WEBROOT=$( echo "${__WEBROOT}" | sed -e "s%/%\\\\/%g")

# replace placeholders cert challenge template
sed -i "" -e "s/__LISTEN__/${__LISTEN}/g"                                     \
          -e "s/__DOMAIN__/${__DOMAIN}/g"                                     \
          -e "s/__ACCESSLOG__/${__ACCESSLOG}/g"                               \
          -e "s/__ERRORLOG__/${__ERRORLOG}/g"                                 \
          -e "s/__WEBROOT__/${__WEBROOT}/g"                                   \
          ${__PROCFILE_C}

# escape path delimiter
__TGTPRX=$( echo "${__TGTPRX}" | sed -e "s%/%\\\\/%g")

# replace placeholders cert redirect template
sed -i "" -e "s/__LISTEN__/${__TGTLISTEN}/g"                                  \
          -e "s/__DOMAIN__/${__DOMAIN}/g"                                     \
          -e "s/__PROXYPASS__/${__TGTPRX}/g"                                  \
          ${__PROCFILE_R}


if [ "${__TEST}" -ne 0 ]; then
  echo "---- cert challenge config ------------------------------------------------"
  echo "------ ${__NGINXCONF_C}"
  cat "${__PROCFILE_C}"
  echo "---- cert redirect config ------------------------------------------------"
  echo "------ ${__NGINXCONF_R}"
  cat "${__PROCFILE_R}"
else
  # At local
  # backup nginx config
  if [ -e ${__NGINXCONF_C} ]; then
    sudo mv "${__NGINXCONF_C}" "${__NGINXCONF_C}.${__PROCDATE}~"
    [ ${__DBG} -ne 0 ] && ls -la "${__NGINXCONF_C}.${__PROCDATE}~"
  fi
  sudo cp ${__PROCFILE_C} ${__NGINXCONF_C}
  # not posix
  # sudo mv -b --suffix=.${__PROCDATE}~ ${__PROCFILE_C} ${__NGINXCONF_C}
  if [ "${__DBG}" -ne 0 ]; then
    cat "${__NGINXCONF_C}"
  fi
  # sudo service nginx reload 2>&1

  # At remote

  # # ControlMaster:  Aggregate TCP sessions
  # # ControlPath:    The path name of the socket for controlling the aggregated TCP session
  # # ControlPersist: Keep the Master connection
  # __SSH_OPT="-q -o ControlMaster=auto -o ControlPath=/tmp/acme-%r@%h:%p -o ControlPersist=5"
  # # Create TEMP Dir
  # __TMP_R=$(sudo -u ${__DUSER} ssh -n ${__SSH_OPT} ${__TARGET} mktemp -d)

  # sudo -u ${__DUSER} scp ${__SSH_OPT} ${__PROCFILE_R} ${__TARGET}:${__TMPDIR}/$(basename ${__PROCFILE_R})

  # # sudo -u ${__DUSER} ssh -n ${__SSH_OPT}
  # # sudo -u ${__DUSER} ssh ${__SSH_OPT} ${__TARGET} "/bin/sh -C \" ls -la \" "

  # # sudo -u ${__DUSER} ssh      -n ${__SSH_OPT} ${__TARGET} rm -rf ${__TMP_R}
  # sudo -u ${__DUSER} ssh -O exit ${__SSH_OPT} ${__TARGET}

fi

