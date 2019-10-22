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
GETSTORAGE=1
GETOPENFILES=1
GETHARDWARE=1
GETSYSLOGS=1
GETNETCONF=1
GETNTPCONFIG=1
GETINIINFO=1

SDATE=$(date +%F_%T | tr ":" '-')
WKDIR=/tmp/support-report_$(hostname)_${SDATE}
INPROGRESS_FILE="/tmp/support_report.in_progress"
REPORTFILE="support-report_$(hostname)_${SDATE}.tar.gz"


# we cannot assume linux flavor, and path for tools are sometimes different or tools are not present at all on customer's server
function assign_command()
{
	_cmd=$(which $1 2>/dev/null)
	_cmd=${_cmd:=message "missing command: $1"}
	echo ${_cmd}
}

VIRT_WHAT=$(assign_command virt_what)
LSB_RELEASE=$(assign_command lsb_release)
LSPCI=$(assign_command lspci)
IPTABLES=$(assign_command iptables)
VMWARE_CHECKVM=$(assign_command vmware-checkvm)
VMWARE_TOOLBOX_CMD=$(assign_command vmware-toolbox-cmd)
COPY_PRESERVE_COMMAND="cp -af"
SS=$(assign_command ss)
IP=$(assign_command ip)
LSMOD=$(assign_command lsmod)
LSOF=$(assign_command lsof)
LSBLK=$(assign_command lsblk)
NTPQ=$(assign_command ntpq)

# collection files
SYSTEM_CONFIGFILE=$WKDIR/11-system-config.txt
SYSTEM_PACKAGESFILE=$WKDIR/12-installed-software.txt
VM_CONFIGFILE=$WKDIR/13-vm-system.txt
STORAGE_CONFIGFILE=$WKDIR/14-storage.txt
OPENFILES=$WKDIR/15-openfiles.txt
HWCONF=$WKDIR/16-hw-config.txt
NETCONF=$WKDIR/17-net-config.txt
LOGS=$WKDIR/system-logs
SYSCTL=$WKDIR/18-sysctl.txt
SLABINFO=$WKDIR/19-slabinfo.txt
SYSTREE=$WKDIR/20-systree.txt
CRONFILES=$WKDIR/21-cronfiles.txt
HOSTSFILE=$WKDIR/22-hosts
RESOLVFILE=$WKDIR/23-resolv.conf
ROOTCRON=$WKDIR/24-root-crontab.txt
NTPCONFIG=$WKDIR/25-ntp-config.txt
INITSCRIPTS=$WKDIR/26-initscripts.txt

# product specific paths and variables
APPD_SYSTEM_LOG_FILE="/tmp/support_report.log"
APPLOGS=$WKDIR/app-logs
REPORTPATH=/tmp/download
ADDITIONAL_CONFIG_FILES="/etc/resolv.conf"

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
        echo -e "$(basename $0) ver. $VERSION" >> $SYSTEM_CONFIGFILE
        echo -e "Host: $(hostname -f) - Compiled on $(date +%c) by $(whoami)\n" >> $SYSTEM_CONFIGFILE
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
        echo -en "=================================\nOperating System\n---------------------------------\n" >> $SYSTEM_CONFIGFILE
        uname -a >> $SYSTEM_CONFIGFILE

 	[[ -f /etc/redhat-release ]] && $( head -1 /etc/redhat-release >> $SYSTEM_CONFIGFILE )
        [[ -f /etc/debian_version ]] && $( head -1 /etc/debian_version >> $SYSTEM_CONFIGFILE )
        

        if [[ -x $LSB_RELEASE ]]; then
                $LSB_RELEASE -a >> $SYSTEM_CONFIGFILE
        fi
        
        echo -en "=================================\nLoaded Modules\n---------------------------------\n" >> $SYSTEM_CONFIGFILE
        $LSMOD >> $SYSTEM_CONFIGFILE

        if [ -f /etc/modules.conf ]; then
                cp -a /etc/modules.conf $WKDIR
        elif [ -f /etc/modprobe.conf ]; then
                cp -a /etc/modprobe.conf* $WKDIR
        fi

       echo -en "=================================\nLast logins\n---------------------------------\n" >> $SYSTEM_CONFIGFILE
       last -20 >> $SYSTEM_CONFIGFILE

       sysctl -A 2>/dev/null > $SYSCTL
       
	[ $ROOT_MODE -eq 1 ] && cat /proc/slabinfo > $SLABINFO
        
       [ -d /sys ] && ls -laR /sys 2>/dev/null > $SYSTREE  
       
       
        # Get list of cron jobs
        ls -lr /etc/cron* > $CRONFILES
        
        [ $ROOT_MODE ] && [ -f /var/spool/cron/tabs/root ] && crontab -l > $ROOTCRON

        $COPY_PRESERVE_COMMAND /etc/hosts $HOSTSFILE
        $COPY_PRESERVE_COMMAND /etc/resolv.conf  $RESOLVFILE
        ADDITIONAL_CONFIG_FILE_LIST=$(echo $ADDITIONAL_CONFIG_FILES | tr ',' ' ');
        for CONFIG_FILE in $ADDITIONAL_CONFIG_FILE_LIST; do
            [ -f $CONFIG_FILE ] && cp -a $CONFIG_FILE $WKDIR ;
        done

       
       
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
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "Host time: ") && ( $VMWARE_TOOLBOX_CMD stat hosttime)) >> $VM_CONFIGFILE
        (echo -en "This machine time: " && date ) >> $VM_CONFIGFILE
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "CPU speed: ") && ( $VMWARE_TOOLBOX_CMD stat speed)) >> $VM_CONFIGFILE
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "CPU res: ") && ( $VMWARE_TOOLBOX_CMD stat cpures)) >> $VM_CONFIGFILE
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "CPU limit: ") && ( $VMWARE_TOOLBOX_CMD stat cpulimit)) >> $VM_CONFIGFILE

    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "MEM baloon: ") && ( $VMWARE_TOOLBOX_CMD stat balloon)) >> $VM_CONFIGFILE
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "MEM swap: ") && ( $VMWARE_TOOLBOX_CMD stat swap)) >> $VM_CONFIGFILE
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "MEM res: ") && ( $VMWARE_TOOLBOX_CMD stat memres)) >> $VM_CONFIGFILE
    [[ -x $VMWARE_TOOLBOX_CMD ]] && (  (echo -en "MEM limit: ") && ( $VMWARE_TOOLBOX_CMD stat memlimit)) >> $VM_CONFIGFILE
}


function gethardware()
{
        message -n "Copying hardware profile..."
        echo -en "=================================\nSystem Specs\n---------------------------------\n" >> $HWCONF
        echo "---------- CPU INFO ----------" >> $HWCONF
        cat /proc/cpuinfo >> $HWCONF
        echo "---------- MEM INFO ----------" >> $HWCONF
        cat /proc/meminfo >> $HWCONF
        echo "---------- PCI BUS -----------" >> $HWCONF
        ${LSPCI} >> $HWCONF

        if [[ $ROOT_MODE -eq 1 ]]; then 
            dmidecode >> $HWCONF
        else 
            echo -en "\nScript has been not run by root, full hardware profile could not be collected." >> $HWCONF
        fi
        message "done!"
}

function getnetconf()
{
        echo "=================================" >> $NETCONF
        echo "Network Configuration " >> $NETCONF
        echo "---------- Links Info ----------" >> $NETCONF
        $IP -o -s link >> $NETCONF
        echo "---------- Address Info ----------" >> $NETCONF
        $IP -o address >> $NETCONF
        echo "---------- Routes Info ----------" >> $NETCONF
        $IP -o route >> $NETCONF
        echo "---------- Rules Info ----------" >> $NETCONF
        $IP -o rule >> $NETCONF
        echo "---------- Network sockets ----------" >> $NETCONF
        $SS -anp >> $NETCONF

        if [[ $ROOT_MODE -eq 1 ]]; then 
        echo "---------- Network firewall configuration ----------" >> $NETCONF
            $IPTABLES -L -nv >> $NETCONF
        echo "---------- Network firewall configuration: NAT table ----------" >> $NETCONF
            $IPTABLES -L -t nat -nv >> $NETCONF
        fi
}


function getstorage()
{
       echo -en "=================================\nStorage\n---------------------------------\n" >> $STORAGE_CONFIGFILE
        cat /proc/partitions >> $STORAGE_CONFIGFILE
        echo "----------------------------------" >> $STORAGE_CONFIGFILE
        echo -e "Device Partition table" >> $STORAGE_CONFIGFILE

# limited lskblk output for humans
        $LSBLK -fs -t >> $STORAGE_CONFIGFILE
        echo "----------------------------------" >> $STORAGE_CONFIGFILE
# lskblk output for machine parsing
# different lsblk versions have different possibilities, we want to catch all possible columns
        lsblk_columns=$($LSBLK  -h | grep '^  ' | awk '{print $1 }' |tr '\n' ',')
        $LSBLK -r -i -a --output ${lsblk_columns::-1} >> $STORAGE_CONFIGFILE

        echo "----------------------------------" >> $STORAGE_CONFIGFILE
        df -Th >> $STORAGE_CONFIGFILE
        echo -en "=================================\nMounted File Systems\n---------------------------------\n" >> $STORAGE_CONFIGFILE
        cat /etc/mtab | egrep -i ^/dev | tr -s ' ' ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' >> $STORAGE_CONFIGFILE
        cat /etc/mtab | egrep -iv ^/dev | tr -s ' ' ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' | sort >> $STORAGE_CONFIGFILE
        echo -en "=================================\nConfigured File Systems\n---------------------------------\n" >> $STORAGE_CONFIGFILE
        cat /etc/fstab | egrep -i ^/dev | tr -s [:blank:] ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' | sort >> $STORAGE_CONFIGFILE
        cat /etc/fstab | egrep -iv ^/dev | grep ^[^#] | tr -s [:blank:] ';' | awk -F ';' '{ printf "%-15s %-15s %-10s %-20s %s %s\n",$1,$2,$3,$4,$5,$6 }' | sort >> $STORAGE_CONFIGFILE

}
 
function getopenfiles()
{
        # Print list of open files
        message -en "Reading open files... "
        $LSOF -n -X > $OPENFILES
        message "done!"
} 

function getsyslogs()
{
    message -n "Copying system logs..."

    if [[ $ROOT_MODE -eq 1 ]]; then
        # Get system log for last $DAYS  day
        [ -d $LOGS ] || mkdir $LOGS
        find /var/log -iname messages* -mtime -$DAYS -exec cp -a {} $LOGS \;
        find /var/log -iname boot.* -mtime -$DAYS -exec cp -a {} $LOGS \;
        find /var/log -iname kernel.log* -mtime -$DAYS -exec cp -a {} $LOGS \;
        find /var/log -iname ntp* -mtime -$DAYS -exec cp -a {} $LOGS \;
        find /var/log -iname cron* -mtime -$DAYS -exec cp -a {} $LOGS \;
        dmesg > $LOGS/dmesg

        if [ -d /var/log/sa ]; then
                mkdir $LOGS/sa
                find /var/log/sa -iregex '[a-z/]*sa\.*[0-9_]+' -exec $COPY_PRESERVE_COMMAND {} $LOGS/sa/ \;
        fi

        [ -f /var/log/wtmp ] && $COPY_PRESERVE_COMMAND /var/log/wtmp $LOGS/

        find /var/log -iname roothistory.log* -exec cp -a {} $LOGS \; 2>/dev/null
        message "Done!"
   else
   	# as a non-root user we will be able to get only some crumbs. lets get just everything...
   	find /var/log -mtime -$DAYS -exec cp -a {} $LOGS \; 2>/dev/null
   fi     
} 

function getntpconfig()
{
    message -n "Building ntpconfig..."
    date                 >> $NTPCONFIG
    $NTPQ -n -c peers     >> $NTPCONFIG
    $NTPQ -n -c as  >> $NTPCONFIG
    $NTPQ -n -c sysinfo  >> $NTPCONFIG
    message "done!"
}
 
function getinitinfo()
{
        RUNLEVEL=$(runlevel | egrep -o [0-6abcs])
        echo "Current runlevel: $RUNLEVEL" > $INITSCRIPTS
        ls -l /etc/rc${RUNLEVEL}.d/* >> $INITSCRIPTS
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
[ $GETHARDWARE -eq 1 ] && gethardware
[ $GETSTORAGE -eq 1 ] && getstorage
[ $GETOPENFILES -eq 1 ] && getopenfiles
[ $GETSYSLOGS -eq 1 ] && getsyslogs
[ $GETNETCONF -eq 1 ] && getnetconf
[ $GETNTPCONFIG -eq 1 ] && getntpconfig
[ $GETINIINFO -eq 1 ] && getinitinfo


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
    echo "The support-report can be downloaded from the server Management Console,"
    echo "or from"
    echo "    ${REPORTPATH}/${REPORTFILE}"
        echo "You will be directed where to submit this report by your technical support contact."
        exit 0
else
        message -e "\nReport located in $WKDIR"
        exit 0
fi
