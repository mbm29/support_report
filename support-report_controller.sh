#!/bin/bash
#
# AppDynamics Cisco Technical Support report generator
#

VERSION=
DAYS=30

SDATE=$(date +%F_%T | tr ":" '-')
WKDIR=/tmp/support-report_$(hostname)_${SDATE}
INPROGRESS_FILE="/tmp/support_report.in_progress"
APPDSYSTEMLOGFILE="/tmp/appd_system.log"
CGI=0

ROOT_MODE=1 && [[ "$(whoami)" != "root" ]] && ROOT_MODE=0


function message()
{
  if [ $CGI -eq 0 ]; then
    echo "$@"
  elif [ -f $APPDSYSTEMLOGFILE ]; then
    echo -ne "\n[REPORT] `date` :: $@ \n" >> $APPDSYSTEMLOGFILE 2>&1
  fi
}

function warning()
{
        message "WARNING: $@"
}

function err()
{
        message "ERROR: $1"
        exit 1
}


echo $ROOT_MODE

# [ $(id -u) -ne 0 ] 

[ $ROOT_MODE ] && warning  "You should run this script as root. Only limited information will be available in report."

