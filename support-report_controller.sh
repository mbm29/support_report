#!/bin/bash 
#
# AppDynamics Cisco Technical Support report generator for Controller host
#

VERSION=0.3
DAYS=3
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
GETAPPD=1
GETNUMA=1
GETCONTROLLERLOGS=1
GETCONTROLLERMYSQLLOGS=1
GETCONTROLLERCONFIGS=1
GETLOAD=1
GETUSERLIMITS=1
GETCERTSINFO=1
GETMYSQLQUERIES=1

ROOT_USER="root"
MYSQL_PORT="3388"
SDATE=$(date +%F_%T | tr ":" '-')
WKDIR=/tmp/support-report_$(hostname)_${SDATE}
INPROGRESS_FILE="/tmp/support_report.in_progress"
REPORTFILE="support-report_$(hostname)_${SDATE}.tar.gz"
mysql_password=""


# trap ctrl-c and clean before exit
function clean_after_yourself {
	rm -fr $WKDIR
        rm $INPROGRESS_FILE
}

trap ctrl_c INT
function ctrl_c() {
	clean_after_yourself
        exit
}

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
LSCPU=$(assign_command lscpu)
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
IOSTAT=$(assign_command iostat)
VMSTAT=$(assign_command vmstat)
MPSTAT=$(assign_command mpstat)
TOP=$(assign_command top)
SAR=$(assign_command sar)
DMIDECODE=$(assign_command dmidecode)

# collection files
SYSTEM_CONFIGFILE=$WKDIR/11-system-config.txt
SYSTEM_PACKAGESFILE=$WKDIR/12-installed-software.txt
VM_CONFIGFILE=$WKDIR/13-vm-system.txt
STORAGE_CONFIGFILE=$WKDIR/14-storage.txt
OPENFILES=$WKDIR/15-openfiles.txt
HWCONF=$WKDIR/16-hw-config.txt
NETCONF=$WKDIR/17-net-config.txt
LOGS=$WKDIR/system-logs/
SYSCTL=$WKDIR/18-sysctl.txt
SLABINFO=$WKDIR/19-slabinfo.txt
SYSTREE=$WKDIR/20-systree.txt
CRONFILES=$WKDIR/21-cronfiles.txt
HOSTSFILE=$WKDIR/22-hosts
RESOLVFILE=$WKDIR/23-resolv.conf
ROOTCRON=$WKDIR/24-root-crontab.txt
NTPCONFIG=$WKDIR/25-ntp-config.txt
INITSCRIPTS=$WKDIR/26-initscripts.txt
PACKAGESFILE=$WKDIR/27-packages.txt
NUMAFILE=$WKDIR/28-numa.txt
PERFSTATS=$WKDIR/29-perfstats.txt
APPD_JAVAINFO=$WKDIR/30-javainfo.txt
APPD_MYSQLINFO=$WKDIR/31-mysqlinfo.txt
APPD_INSTALL_USER_LIMITS=$WKDIR/32-install-user-limits.txt
APPD_CERTS=$WKDIR/33-controller-certs.txt
APPD_QUERIES=$WKDIR/34-controller-queries.txt

# product specific paths and variables
APPD_SYSTEM_LOG_FILE="/tmp/support_report.log"
APPLOGS=$WKDIR/controller-logs
APPD_HOME="/opt/appd" #just default
APPD_CONTROLLER_HOME="/opt/appd/platform/product/controller"  #just default, this is re-evaluating later
APPD_CONTROLLER_JAVA_HOME=""
APPD_CONTROLLER_GLASSFISH_PID=
APPD_CONTROLLER_MYSQL_PID=
DOWNLOAD_PATH="/appserver/glassfish/domains/domain1/applications/controller/controller-web_war/download/"
REPORTPATH="\$APPD_CONTROLLER_HOME\$DOWNLOAD_PATH"
CONTROLLERLOGS=$WKDIR/controller-logs/
CONTROLLERMYSQLLOGS=$WKDIR/controller-mysql-logs/
CONTROLLERCONFIGS=$WKDIR/controller-configs/

ADDITIONAL_CONFIG_FILES=""
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
        clean_after_yourself
        exit 1
}

function zipreport()
{
        cd $(dirname $WKDIR)
#       zip -q9r $REPORTPATH/$REPORTFILE $(basename $WKDIR)
# zip could be preferable, easier for CU to review archive, but this tool is not always available.
        tar cfvz $(eval echo ${REPORTPATH})/$REPORTFILE $(basename $WKDIR)
        cd $OLDPWD
        rm -rf $WKDIR

        if [ -f $(eval echo ${REPORTPATH})/$REPORTFILE ]; then
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
        FORMAT="%5s\t%-30s\n"

    echo "Usage: $(basename $0) [ -vcpHlaz ] [ -d days of logs ]"
        printf $FORMAT "-c" "Disable generating system configuration"
        printf $FORMAT "-p" "Disable measuring system load/performance"
        printf $FORMAT "-H" "Disable generating hardware report"
        printf $FORMAT "-l" "Disable gathering system logs"
        printf $FORMAT "-a" "Disable gathering AppD logs"
        printf $FORMAT "-d" "Number of days back of logs to retrieve (default is $DAYS days)"
        printf $FORMAT "-z" "Do not zip report and leave it in /tmp"
        printf $FORMAT "-v" "Version"

        exit 2
}

function getpackages()
{
        echo -n "Building package list..."
        echo linux flavour - $LINUX_FLAVOUR
        [[ ${LINUX_FLAVOUR} = "redhat" ]] && rpm -qa --queryformat "%{NAME} %{VERSION}\n" | sort  >> $PACKAGESFILE
        [[ ${LINUX_FLAVOUR} = "debian" ]] && dpkg-query -W -f='${Package} ${Version}\n' | sort  >> $PACKAGESFILE
        echo "done!"
}

function getlinuxflavour()
{
        _out=$(cat /etc/[A-Za-z]*[_-][rv]e[lr]* | uniq -u)
        [[ $(echo ${_out} | grep -i -E -e '(debian|ubuntu)' | wc -l ) -ge 1 ]] && LINUX_FLAVOUR=debian
        [[ $(echo ${_out} | grep -i -E -e '(rhel|redhat)'| wc -l ) -ge 1 ]] && LINUX_FLAVOUR=redhat
}

function getsystem()
{
        message "Building system configuration..."
        echo "uptime: $(uptime)" >> $SYSTEM_CONFIGFILE
        echo -en "=================================\nOperating System\n---------------------------------\n" >> $SYSTEM_CONFIGFILE
        uname -a >> $SYSTEM_CONFIGFILE



 	[[ -f /etc/redhat-release ]] && $( head -1 /etc/redhat-release >> $SYSTEM_CONFIGFILE )
        [[ -f /etc/debian_version ]] && $( head -1 /etc/debian_version >> $SYSTEM_CONFIGFILE )
        
        cat /etc/*-release | uniq -u >> $SYSTEM_CONFIGFILE
        

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
        # resolv.conf is often symlink
        cp /etc/resolv.conf  $RESOLVFILE
        ADDITIONAL_CONFIG_FILE_LIST=$(echo $ADDITIONAL_CONFIG_FILES | tr ',' ' ');
        for CONFIG_FILE in $ADDITIONAL_CONFIG_FILE_LIST; do
            [ -f $CONFIG_FILE ] && cp -a $CONFIG_FILE $WKDIR ;
        done
        
        getpackages
}        



function getvmware()
{
    grep -q "^flags.*hypervisor" /proc/cpuinfo  && echo "Machine running under VM hypervisor." >> $VM_CONFIGFILE 
    if [[ $ROOT_MODE -eq 1 ]]; then
          echo  -en "\nVM Check: " >> $VM_CONFIGFILE
            VM=`${VIRT_WHAT} 2> /dev/null`
            [[ -z $VM && -x $(${VIRT_WHAT}) ]] && VM=$(${VIRT_WHAT})
            [[ -z $VM ]] && VM="Does not appear to be a VM"
            echo $VM  >> $VM_CONFIGFILE
    fi

    if [[ -x $VMWARE_CHECKVM ]]; then
	$VMWARE_CHECKVM >/dev/null
	if [ $? -eq 0 ]; then
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
	fi
    fi		    
}


function gethardware()
{
        message -n "Copying hardware profile..."
        echo -en "=================================\nSystem Specs\n---------------------------------\n" >> $HWCONF
        echo -e "\n---------------------------------\n Summarised CPU INFO\n ---------------------------------" >> $HWCONF
        ${LSCPU} >> $HWCONF
        echo -e "\n---------------------------------\n Detailed CPU INFO \n ---------------------------------" >> $HWCONF
        cat /proc/cpuinfo >> $HWCONF
        echo -e "\n----------\n MEM INFO\n ----------" >> $HWCONF
        cat /proc/meminfo >> $HWCONF
        echo -e "\n---------- \n PCI BUS \n-----------" >> $HWCONF
        ${LSPCI} >> $HWCONF

        if [[ $ROOT_MODE -eq 1 ]]; then 
            ${DMIDECODE} >> $HWCONF
        else
           echo -e "\n---------- \ndmidecode \n-----------" >> $HWCONF
           sudo --non-interactive ${DMIDECODE} >> $HWCONF
           echo -en "\nScript has been not run by root, full hardware profile could not be collected." >> $HWCONF
        fi
        message "done!"
}

function getnetconf()
{
        echo "=================================" >> $NETCONF
        echo "Network Configuration " >> $NETCONF
        echo -e "\n---------- Links Info ----------" >> $NETCONF
        $IP -o -s link >> $NETCONF
        echo -e "\n---------- Address Info ----------" >> $NETCONF
        $IP -o address >> $NETCONF
        echo -e "\n---------- Routes Info ----------" >> $NETCONF
        $IP -o route >> $NETCONF
        echo -e "\n---------- Rules Info ----------" >> $NETCONF
        $IP -o rule >> $NETCONF
        echo -e "\n---------- Network sockets ----------" >> $NETCONF
        $SS -anp >> $NETCONF

        if [[ $ROOT_MODE -eq 1 ]]; then 
        echo -e "\n---------- Network firewall configuration ----------" >> $NETCONF
            $IPTABLES -L -nv >> $NETCONF
        echo -e "\n---------- Network firewall configuration: NAT table ----------" >> $NETCONF
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
        $LSOF -n -b -w -P -X > $OPENFILES
        message "done!"
}

function getsyslogs()
{
    message -n "Copying system logs..."
    [ -d $LOGS ] || mkdir $LOGS
    if [[ $ROOT_MODE -eq 1 ]]; then
        # Get system log for last $DAYS  day
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
   	find /var/log -name "*.*" -mtime -$DAYS -exec cp -a {} $LOGS \; 2>/dev/null
        dmesg > $LOGS/dmesg
   fi     
} 

function getntpconfig()
{
    message -n "Building ntpconfig..."
    echo -e "\n---------- current system date and time ----------" >> $NTPCONFIG    
    date                 >> $NTPCONFIG
    echo -e "\n---------- current hardware date and time ----------" >> $NTPCONFIG    
    hwclock --get                 >> $NTPCONFIG    
    echo -e "\n---------- NTP peers ----------" >> $NTPCONFIG
    $NTPQ -n -c peers     >> $NTPCONFIG
    echo -e "\n---------- NTP associations ----------" >> $NTPCONFIG    
    $NTPQ -n -c as  >> $NTPCONFIG
    echo -e "\n---------- NTP sysinfo ----------" >> $NTPCONFIG    
    $NTPQ -n -c sysinfo  >> $NTPCONFIG
    message "done!"
}
 
function getinitinfo()
{
        RUNLEVEL=$(runlevel | egrep -o [0-6abcs])
        echo "Current runlevel: $RUNLEVEL" > $INITSCRIPTS
        ls -l /etc/rc${RUNLEVEL}.d/* >> $INITSCRIPTS
}


function subpath()
{
        echo "$1" |rev  | cut -d"/" -f $2- | rev
}

function appd_variables()
{
#/appdynamics/platform/product/controller/appserver/glassfish/domains/domain1/config
        APPD_CONTROLLER_GLASSFISH_PID=$(pgrep -f "s/glassfish.jar ")
        APPD_CONTROLLER_MYSQL_PID=$(pgrep -f "[d]b/bin/mysqld")
        if [[ -n $APPD_CONTROLLER_GLASSFISH_PID ]]; then
       	       	if ! [[ "$(whoami)" =~ ^("$(ps xau | grep $APPD_CONTROLLER_GLASSFISH_PID | tail -1 | cut -d' ' -f 1)"|root) ]]; then        	
		        err "You must run this tool as root or as the same user who is running appd processes"
		fi
                APPD_HOME=$(subpath $(readlink /proc/$APPD_CONTROLLER_GLASSFISH_PID/cwd) 9)
                APPD_CONTROLLER_HOME=$(subpath $(readlink /proc/$APPD_CONTROLLER_GLASSFISH_PID/cwd) 6)
                APPD_CONTROLLER_JAVA_HOME=$(subpath $(readlink /proc/$APPD_CONTROLLER_GLASSFISH_PID/exe) 3)
        else # controller is not running, we need to figureout all paths differently
        # lets check if just controller DB is running ?
        	if [[ -n $APPD_CONTROLLER_MYSQL_PID ]]; then
        	       	if ! [[ "$(whoami)" =~ ^("$(ps xau | grep $APPD_CONTROLLER_MYSQL_PID | tail -1 | cut -d' ' -f 1)"|root) ]]; then
			        err "You must run this tool as root or as the same user who is running appd processes"
			fi
#/appdynamics/platform/product/controller/db/data
	                APPD_HOME=$(subpath $(readlink /proc/$APPD_CONTROLLER_MYSQL_PID/cwd) 6)
        	        APPD_CONTROLLER_HOME=$(subpath $(readlink /proc/$APPD_CONTROLLER_MYSQL_PID/cwd) 3)
                else # controller and DB are not running. so sad... lets try something else yet
			_dir=$(find / -name controller.sh -print -quit 2>/dev/null)
#/appdynamics/platform/product/controller/bin/controller.sh			
                	APPD_HOME=$(subpath $_dir 6)
                	APPD_CONTROLLER_HOME=$(subpath $_dir 3)
        	fi
        fi
        APPD_CONTROLLER_INSTALL_USER=$(awk -F= '$1 ~ /^\s*user/ {print $2}' ${APPD_CONTROLLER_HOME}/db/db.cnf)
            if [ -z "${APPD_CONTROLLER_INSTALL_USER}" ] ; then
               APPD_CONTROLLER_INSTALL_USER=${ROOT_USER}
            fi
        APPD_DB_INSTALL_PORT=$(awk -F= '$1 ~ /^\s*port/ {print $2}' ${APPD_CONTROLLER_HOME}/db/db.cnf)
            if [ -z "${APPD_DB_INSTALL_PORT}" ] ; then
               APPD_DB_INSTALL_PORT=${MYSQL_PORT}
            fi
}

function get_mysql_password()
{
if [ -z $mysql_password ]
	then
	printf "MySQL root user password: "
	read -e -r -s -t15 mysql_password
	echo ""
fi
}


function get_mysql_data()
{
MYSQL="${APPD_CONTROLLER_HOME}/db/bin/mysql"
mysqlopts="-A -t -vvv --force --host=localhost --protocol=TCP --user=root "
echo -e "\n---------- Controller Profile Information ---------- " >> $APPD_QUERIES
$MYSQL $mysqlopts --port=$APPD_DB_INSTALL_PORT --password=$mysql_password > $APPD_QUERIES <<EOF
use controller;
select version() mysql_version;
select name, value from global_configuration_cluster where name in ('schema.version', 'performance.profile','appserver.mode','ha.controller.type');
select from_unixtime(ts_min*60), NOW(), count(distinct(node_id)), count(*) from metricdata_min where ts_min > (select max(ts_min) - 10 from metricdata_min) group by 1 order by 1;
select from_unixtime(ts_min*60), NOW(), count(distinct(node_id)), count(*) metric_count from metricdata_hour where ts_min > (select max(ts_min) - 10080 from metricdata_hour) group by 1 ORDER BY metric_count DESC LIMIT 10;
SELECT table_name FROM   information_schema.key_column_usage WHERE  table_name LIKE 'metricdata%' AND table_name != 'metricdata_min' AND table_name != 'metricdata_min_agg' AND column_name = 'ts_min' AND ordinal_position = 1;
select name,value from global_configuration;
select * from notification_config\G;
EOF
}

function appd_getenvironment()
{
    if [[ -n $APPD_CONTROLLER_GLASSFISH_PID ]]; then
        echo -e "\n---------- Controller Java PID ---------- " >> $APPD_JAVAINFO
        echo $APPD_CONTROLLER_GLASSFISH_PID >> $APPD_JAVAINFO
        echo -e "\n---------- Controller Java version ---------- " >> $APPD_JAVAINFO
		/proc/$APPD_CONTROLLER_GLASSFISH_PID/exe -version >> $APPD_JAVAINFO 2>&1
	 	echo -e "\n---------- Controller Java limits ---------- " >> $APPD_JAVAINFO
		cat /proc/$APPD_CONTROLLER_GLASSFISH_PID/limits >> $APPD_JAVAINFO
	 	echo -e "\n---------- Controller Java status ---------- " >> $APPD_JAVAINFO
		cat /proc/$APPD_CONTROLLER_GLASSFISH_PID/status >> $APPD_JAVAINFO
	 	echo -e "\n---------- Controller Java scheduler stats ---------- " >> $APPD_JAVAINFO
		 # use the source, Luke! 	kernel/sched/debug.c
		cat /proc/$APPD_CONTROLLER_GLASSFISH_PID/sched >> $APPD_JAVAINFO
	else
                echo -e "Controller Java process is not running." >> $APPD_JAVAINFO
	fi

	if [[ -n $APPD_CONTROLLER_MYSQL_PID ]]; then
	    echo -e "\n---------- Controller MySQL PID ---------- " >> $APPD_MYSQLINFO
        echo $APPD_CONTROLLER_MYSQL_PID >> $APPD_MYSQLINFO
        echo -e "\n---------- Controller MySQL version ---------- " >> $APPD_MYSQLINFO
		/proc/$APPD_CONTROLLER_MYSQL_PID/exe --version >> $APPD_MYSQLINFO 2>&1
	 	echo -e "\n---------- Controller MySQL limits ---------- " >> $APPD_MYSQLINFO
		cat /proc/$APPD_CONTROLLER_MYSQL_PID/limits >> $APPD_MYSQLINFO
	 	echo -e "\n---------- Controller MySQL status ---------- " >> $APPD_MYSQLINFO
		cat /proc/$APPD_CONTROLLER_MYSQL_PID/status >> $APPD_MYSQLINFO
	 	echo -e "\n---------- Controller MySQL scheduler stats ---------- " >> $APPD_MYSQLINFO
		 # use the source, Luke! 	kernel/sched/debug.c
		cat /proc/$APPD_CONTROLLER_MYSQL_PID/sched >> $APPD_MYSQLINFO
		
		# some information about db size and files
		echo -e "\n---------- Controller MySQL files ---------- " >> $APPD_MYSQLINFO
		ls -la ${APPD_CONTROLLER_HOME}/db/data >> $APPD_MYSQLINFO
		echo -e "\n---------- Controller MySQL file size ---------- " >> $APPD_MYSQLINFO		
		du -hs ${APPD_CONTROLLER_HOME}/db/data/* >> $APPD_MYSQLINFO
	else
                echo -e "Controller MySQL process is not running." >> $APPD_MYSQLINFO
	fi
}

function get_keystore_info()
{
        echo -e "\n---------- Controller Keystore content ---------- " >> $APPD_CERTS
	$APPD_CONTROLLER_JAVA_HOME/bin/keytool -list --storepass "changeit" -rfc  -keystore ${APPD_CONTROLLER_HOME}/appserver/glassfish/domains/domain1/config/keystore.jks >> $APPD_CERTS
	$APPD_CONTROLLER_JAVA_HOME/bin/keytool -list --storepass "changeit" -v  -keystore ${APPD_CONTROLLER_HOME}/appserver/glassfish/domains/domain1/config/keystore.jks >> $APPD_CERTS
}

function getnumastats()
{
 	echo -e "\n---------- Numa inventory of available nodes on the system ---------- " >> $NUMAFILE
	numactl -H >> $NUMAFILE
 	echo -e "\n---------- per-NUMA-node memory statistics for operating system ---------- " >> $NUMAFILE
	numastat >> $NUMAFILE
	echo -e "\n---------- per-NUMA-node memory statistics for java and mysql processes ---------- " >> $NUMAFILE
	numastat -czmns java mysql  >> $NUMAFILE
}

function getcontrollerlogs()
{
        [ -d $CONTROLLERLOGS ] || mkdir $CONTROLLERLOGS
	find $APPD_CONTROLLER_HOME/logs/ -name "*.*" -mtime -$DAYS -exec cp -a {} $CONTROLLERLOGS \;
}

function getmysqlcontrollselogs()
{
#/appdynamics/platform/product/controller/db/logs/
        [ -d $CONTROLLERMYSQLLOGS ] || mkdir $CONTROLLERMYSQLLOGS
        find $APPD_CONTROLLER_HOME/db/logs/ -name "*.*" -mtime -$DAYS -exec cp -a {} $CONTROLLERMYSQLLOGS \;
}

function getcontrollerconfigs()
{
#/appdynamics/platform/product/controller/appserver/glassfish/domains/domain1/config
        [ -d $CONTROLLERCONFIGS ] || mkdir $CONTROLLERCONFIGS
	find $APPD_CONTROLLER_HOME/appserver/glassfish/domains/domain1/config -name "*.*" -exec cp -a {} $CONTROLLERCONFIGS \;
	find $APPD_CONTROLLER_HOME/db/ -name "*.cnf" -exec cp -a {} $CONTROLLERCONFIGS \;
	find $APPD_CONTROLLER_HOME/ -name "*.lic" -exec cp -a {} $CONTROLLERCONFIGS \;
}


# strings platform/mysql/data/platform_admin/configuration_store.ibd | grep "JobcontrollerRootUserPassword" | tail -1 | awk -F'"' '{print $2}'^C
function getmysqlcontrollerpass()
{
	# root password for controller can be stored in few places. we will try to find it.
	# EC db
	[[ -f $APPD_HOME/platform/mysql/data/platform_admin/configuration_store.ibd ]] && pass=$(strings $APPD_HOME/platform/mysql/data/platform_admin/configuration_store.ibd | grep "JobcontrollerRootUserPassword" | tail -1 | awk -F'"' '{print $2}')
	echo $pass
}


function getloadstats()
{
                message -n "Measuring basic system load... "
	        echo -en "=================================\nDisk IO usage\n---------------------------------\n" >> $PERFSTATS
                $IOSTAT -myxd 5 3 >> $PERFSTATS
	        echo -en "=================================\nCPU and interrupts usage\n---------------------------------\n" >> $PERFSTATS
                $MPSTAT -A 5 3 >> $PERFSTATS
                echo -en "=================================\nMemory Utilization\n---------------------------------\n" >> $PERFSTATS
                $VMSTAT 5 3 >> $PERFSTATS
                echo -en "=================================\nNetwork Utilization\n---------------------------------\n" >> $PERFSTATS
                $SAR -n DEV 30 2 >> $PERFSTATS
                message "done!"
}

function getinstalluserlimits()
{
            message -n "Fetching install user ulimits... "
            echo -en "=================================\nInstall User\n---------------------------------\n" >> $APPD_INSTALL_USER_LIMITS
            echo $APPD_CONTROLLER_INSTALL_USER >> $APPD_INSTALL_USER_LIMITS
	        echo -en "=================================\nulimits\n---------------------------------\n" >> $APPD_INSTALL_USER_LIMITS
            sudo --non-interactive su - $APPD_CONTROLLER_INSTALL_USER -c "ulimit -a" >> $APPD_INSTALL_USER_LIMITS
}



while getopts ":aclpwvzdP:" opt; do
        case $opt in
                a  )    GETCONTROLLERLOGS=0
                                ;;
                c  )    GETCONFIG=0
                                ;;
                p  )    GETLOAD=0
                                ;;
                w  )    GETHARDWARE=0
                                ;;
                l  )    GETSYSLOGS=0
                                ;;
                z  )    ZIPREPORT=0
                                ;;
                d  )    DAYS=$OPTARG
                                ;;
                P)
                        mysql_password=$OPTARG
                                ;;
                v  )    version
                                ;;
                \? )   usage
                                ;;
        esac
done


[ $ROOT_MODE -eq 0 ] && warning  "You should run this script as root. Only limited information will be available in report."

# dont allow to run more than one report collection at once
if [ -f $INPROGRESS_FILE ]
then
    err "Generation of support report in progress. Exiting.";
    exit 1;
fi
touch $INPROGRESS_FILE;
echo $REPORTFILE > $INPROGRESS_FILE;


# Setup work environment
getlinuxflavour
appd_variables
get_mysql_password
[ -d $WKDIR ] || $( mkdir -p $WKDIR && cd $WKDIR )
[ $? -eq '0' ] || err "Could not create working directory $WKDIR"
[ -d $(eval echo ${REPORTPATH}) ] || $( mkdir -p $(eval echo ${REPORTPATH}) )
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
[ $GETAPPD -eq 1 ] && appd_getenvironment
[ $GETNUMA -eq 1 ] && getnumastats
[ $GETCONTROLLERLOGS -eq 1 ] && getcontrollerlogs
[ $GETCONTROLLERMYSQLLOGS -eq 1 ] && getmysqlcontrollselogs
[ $GETCONTROLLERCONFIGS -eq 1 ] && getcontrollerconfigs
[ $GETLOAD -eq  1 ] && getloadstats
[ $GETUSERLIMITS -eq  1 ] && getinstalluserlimits
[ $GETCERTSINFO -eq  1 ] && get_keystore_info
[ $GETMYSQLQUERIES -eq  1 ] && get_mysql_data

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
    echo "   $(eval echo ${REPORTPATH})/${REPORTFILE}"
    echo -e " or \nhttps://$(ip ro g 8.8.8.8| grep src | awk '{print $7}'):8181/controller/download/${REPORTFILE}"
        echo "You will be directed where to submit this report by your technical support contact."
        exit 0
else
        message -e "\nReport located in $WKDIR"
        exit 0
fi
