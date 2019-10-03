#!/bin/bash 
#
# AppDynamics Cisco Technical Support report generator for Controller host
#

VERSION=0.1
DAYS=30
ZIPREPORT=1
CGI=0
GETSYSTEM=1
GETVM=1

SDATE=$(date +%F_%T | tr ":" '-')
WKDIR=/tmp/support-report_$(hostname)_${SDATE}
INPROGRESS_FILE="/tmp/support_report.in_progress"
REPORTFILE="support-report_$(hostname)_${SDATE}.tar.gz"

# we cannot assume linux flavor, and path for tools are sometimes different or tools are not present at all on customer's server
VIRT_WHAT=$(which virt_what 2>/dev/null)
LSB_RELEASE=$(which lsb_release 2>/dev/null)
LSPCI=$(which lspci 2>/dev/null)
IPTABLES=$(which iptables 2>/dev/null)
VMWARE_CHECKVM=$(which vmware-checkvm 2>/dev/null)
VMWARE_TOOLBOX_CMD=$(which vmware-toolbox-cmd 2>/dev/null)

# collection files
SYSTEM_CONFIGFILE=$WKDIR/00-system-config.txt
SYSTEM_PACKAGESFILE=$WKDIR/12-installed-software.txt
VM_CONFIGFILE=$WKDIR/22-vm-system.txt

# product specific paths and variables
APPD_SYSTEM_LOG_FILE="/tmp/support_report.log"
REPORTPATH=/tmp/download


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


function zipreport()
{
        cd $(dirname $WKDIR)
#       zip -q9r $REPORTPATH/$REPORTFILE $(basename $WKDIR)
# zip could be preferable, easier for CU to review archive, but this tool is not always available.
        tar cfvz $REPORTPATH/$REPORTFILE $(basename $WKDIR)
        cd $OLDPWD
        rm -rf $WKDIR

        if [ -f $REPORTPATH/$REPORTFILE ]; then
                echo $REPORTFILE
        else
                err "Report $REPORTFILE  could not be created"
        fi
}


function version()
{
   echo "$(basename $0) v$VERSION"
   exit 2
}


function reportheader()
{
        message "Generating report..."
        echo -en "$(basename $0) $VERSION" >> $SYSTEM_CONFIGFILE
        echo -en "Host: $(hostname -f) - Compiled on $(date +%c) by $(whoami)\n" >> $SYSTEM_CONFIGFILE
}


function usage()
{
	: 
}



function getpackages()
{
        message -n "Building package list..."
        rpm -qa | sort  >> $PACKAGEFILE
        message "done!"
}



function getsystem()
{
        message "Building system configuration..."
        echo -en "==================================== Operating System ================================= \n" >> $SYSTEM_CONFIGFILE
        uname -a >> $SYSTEM_CONFIGFILE

 	[[ -f /etc/redhat-release ]] && $( head -1 /etc/redhat-release >> $SYSTEM_CONFIGFILE )
        [[ -f /etc/debian_version ]] && $( head -1 /etc/debian_version >> $SYSTEM_CONFIGFILE )
        

        if [[ -x $LSB_RELEASE ]]; then
                $LSB_RELEASE -a >> $SYSTEM_CONFIGFILE
        fi

        echo -en "================================= System Specs ================================= \n" >> $SYSTEM_CONFIGFILE
        echo "---------- CPU INFO ----------" >> $SYSTEM_CONFIGFILE        
        cat /proc/cpuinfo >> $SYSTEM_CONFIGFILE
        echo "---------- MEM INFO ----------" >> $SYSTEM_CONFIGFILE
        cat /proc/meminfo >> $SYSTEM_CONFIGFILE
        echo "---------- PCI BUS -----------" >> $SYSTEM_CONFIGFILE
        ${LSPCI} >> $SYSTEM_CONFIGFILE
}        

function getvmware()
{
    if [[ $ROOT_MODE -eq 1 ]]; then
  	  echo  -en "\nVM Check: " >> $VM_CONFIGFILE
	    VM=`${VIRT_WHAT} 2> /dev/null`
	    [[ -z $VM && -x $(${VIRT_WHAT}) ]] && VM=$(${VIRT_WHAT})
	    [[ -z $VM ]] && VM="Does not appear to be a VM"
	    echo $VM  >> $VM_CONFIGFILE
    fi
    
    [[ -x $VMWARE_CHECKVM ]] && $( $VMWARE_CHECKVM -h >> $VM_CONFIGFILE)
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "cpu res") && ( $VMWARE_TOOLBOX_CMD stat cpures) >> $VM_CONFIGFILE)
    
}
 
 
function getstorage()
{        
        echo -en "=================================\nStorage\n---------------------------------\n" >> $SYSTEM_CONFIGFILE
        cat /proc/partitions >> $CONFIGFILE
        echo "----------------------------------" >> $CONFIGFILE
        printf "%-20s%-8s\n" "Device" "Partition table" >> $CONFIGFILE
#        for DEV in $(egrep -o '[sh]d[a-z]$' /proc/partitions); do
#                TYPE=$(parted /dev/${DEV} print | egrep "Disk label|Partition Table" | cut -f2 -d':')
#                printf "%-20s%-8s\n" "/dev/${DEV}" "$TYPE" >> $CONFIGFILE
#        done

        echo "----------------------------------" >> $CONFIGFILE
        df -Th >> $CONFIGFILE
        echo -en "=================================\nMounted File Systems\n---------------------------------\n" >> $CONFIGFILE
        cat /etc/mtab | egrep -i ^/dev | tr -s ' ' ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' >> $CONFIGFILE
        cat /etc/mtab | egrep -iv ^/dev | tr -s ' ' ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' | sort >> $CONFIGFILE
        echo -en "=================================\nConfigured File Systems\n---------------------------------\n" >> $CONFIGFILE
        cat /etc/fstab | egrep -i ^/dev | tr -s [:blank:] ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' | sort >> $CONFIGFILE
        cat /etc/fstab | egrep -iv ^/dev | tr -s [:blank:] ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' | sort >> $CONFIGFILE

        echo -en "=================================\nNetwork Configuration\n---------------------------------\n" >> $CONFIGFILE
        ifconfig -a >> $CONFIGFILE
        echo -en "\n---------------------------------\n" >> $CONFIGFILE
        route -n >> $CONFIGFILE
        echo -en "=================================\nLoaded Modules\n---------------------------------\n" >> $CONFIGFILE
        $LSMOD >> $CONFIGFILE

        RUNLEVEL=$(runlevel | egrep -o [0-6abcs])
        echo "Current runlevel: $RUNLEVEL" > $INITSCRIPTS
        if [ "$OS" == "suse" ]; then
                ls -l /etc/init.d/rc${RUNLEVEL}.d/ >> $INITSCRIPTS
        elif [ "$OS" == "redhat" ]; then
                ls -l /etc/rc${RUNLEVEL}.d/ >> $INITSCRIPTS
        fi

        IPTABLES=$(which iptables)
        if [[ -x $IPTABLES ]]; then
                $IPTABLES -L -n > $FIREWALLREPORT
        fi

        if [ -f /etc/modules.conf ]; then
                cp -a /etc/modules.conf $WKDIR
        elif [ -f /etc/modprobe.conf ]; then
                cp -a /etc/modprobe.conf* $WKDIR
        fi

        sysctl -A 2>/dev/null > $SYSCTL
        cat /proc/slabinfo > $SLABINFO

        [ -d /sys ] && $TREE /sys > $DEVICETREE

        # Get list of cron jobs
        ls -lr /etc/cron* > $CRONFILES
        [ -f /var/spool/cron/tabs/root ] && crontab -l > $ROOTCRON

        $COPY_PRESERVE_COMMAND /etc/hosts $HOSTSFILE
        ADDITIONAL_CONFIG_FILE_LIST=$(echo $ADDITIONAL_CONFIG_FILES | tr ',' ' ');
        for CONFIG_FILE in $ADDITIONAL_CONFIG_FILE_LIST; do
            [ -f $CONFIG_FILE ] && cp -a $CONFIG_FILE $WKDIR ;
        done



    message "done!"
}



[ $ROOT_MODE ] && warning  "You should run this script as root. Only limited information will be available in report."


# dont allow to run more than one report collection at once
if [ -f $INPROGRESS_FILE ]
then
    err "Generation of support report in progress. Exiting.";
    exit 1;
fi
touch $INPROGRESS_FILE;
echo $REPORTFILE > $INPROGRESS_FILE;




# Setup work environment
[ -d $WKDIR ] || $( mkdir $WKDIR && cd $WKDIR )
[ $? -eq '0' ] || err "Could not create working directory $WKDIR"
[ -d $REPORTPATH ] || $( mkdir $REPORTPATH )
cd $WKDIR
reportheader

# collect reports
[ $GETSYSTEM -eq 1 ] && getsystem
[ $GETVM -eq 1 ] && getvmware






# Make all report files readable
chmod -R a+rX $WKDIR

if [ -f $INPROGRESS_FILE ]
then
    rm -f $INPROGRESS_FILE;
fi

if [ $CGI -eq 1 ]; then
        REPORT=$(zipreport)
        echo "${REPORT}"
        exit 0
elif [ $ZIPREPORT -eq 1 ]; then
        message -n "Creating report archive... "
        REPORT=$(zipreport)
        message "Done "
    echo
    echo "The support-report can be downloaded from the servers Management Console,"
    echo "or from"
    echo "    ${REPORTPATH}/${REPORTFILE}"
        echo "You will be directed where to submit this report by your technical support contact."
        exit 0
else
        message -e "\nReport located in $WKDIR"
        exit 0
fi


