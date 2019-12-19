# AppDynamics support_report (controller) tool

## Overview -
A technical support tool that facilitates (both support engineer and client) the process of collecting and archiving data for troubleshooting or identifying system issues.
It gathers general operating system information including hardware specific information, logs and configuration - both from AppDynamics Controller application and OS wide. All this information might be (and usually are) vital to correctly identify issues that the customer is facing.
After report generation, the entire report archive is stored in a default location and may be reviewed before sending to technical support. End customer can easily review what information are gathered, and if customer don't want to share some specific information - they can easily disable collecting it.
Tool is reliable (to some extent), will work on most linux flavours and will not crash if some fundamental tool is unavailable.

## How it works
The tool is made as a bash script and tries to gather information about the system from generally available places and basic system tools. If some particular tool is not present in the customer's environment - script will keep working, informing only about that fact. Script is supposed to detect Linux flavor, adjusting all needed paths and behavior according to this.

As AppDynamics applications can be installed freely in *any* directory on server, and support_report is not an official part of the controller package, it needs to detect correctly where actually are all the interesting files.
It is quite easy when controller process is running but since it is a troubleshooting tool - it cannot assume the easiest way, rather the contrary. In such case, when there are no running appd processes, it tries to find the correct path by "brute force" - by finding a specific file on the server.

Script can be run by regular user or by root, but only when running by root it will be able to collect all information and logs, however, it will not crash or give up when running as a regular user.

All of the above, make dependencies and requirements very low, allowing to work accurately on any machine. 


## Usage

# ./support-report_controller.sh --help
Usage: support-report_controller.sh [ -vcpHlaz ] [ -d days of logs ]
   -c	Disable generating system configuration
   -p	Disable measuring system load/performance
   -H	Disable generating hardware report
   -l	Disable gathering system logs
   -a	Disable gathering AppD logs
   -d	Number of days back of logs to retrieve (default is 3 days)
   -z	Do not zip report and leave it in /tmp
   -v	Version

# Example output

```
root@ip-172-31-33-13:/appdynamics/platform/support_report# ./support-report_controller.sh
MySQL root user password:
Generating report...
Building system configuration...
No LSB modules are available.
Building package list...linux flavour - debian
done!
Copying hardware profile...done!
Reading open files... done!
Copying system logs...Done!
Building ntpconfig...done!
Measuring basic system load... done!
Fetching install user ulimits... mysql: [Warning] Using a password on the command line interface can be insecure.
Creating report archive... Done

The support-report can be downloaded from the server Management Console,
or from
   /appdynamics/platform/product/controller/appserver/glassfish/domains/domain1/applications/controller/controller-web_war/download//support-report_ip-172-31-33-13_2019-12-19_13-21-27.tar.gz
 or
https://172.31.33.13:8181/controller/download/support-report_ip-172-31-33-13_2019-12-19_13-21-27.tar.gz
You will be directed where to submit this report by your technical support contact.

```
Support report artifact is a compressed tar archive, with text files consisting information about running system, appd controller and directories with logs and configs.
Here is example, number of included files proabbly will varry, as there are still plans to implement more functionality.

```

root@ip-172-31-33-13:/appdynamics/platform/support_report# tar tfz  /appdynamics/platform/product/controller/appserver/glassfish/domains/domain1/applications/controller/controller-web_war/download/support-report_ip-172-31-33-13_2019-12-19_13-21-27.tar.gz --exclude='*/*/*' | sort -n
support-report_ip-172-31-33-13_2019-12-19_13-21-27/
support-report_ip-172-31-33-13_2019-12-19_13-21-27/11-system-config.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/13-vm-system.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/14-storage.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/15-openfiles.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/16-hw-config.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/17-net-config.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/18-sysctl.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/19-slabinfo.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/20-systree.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/21-cronfiles.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/22-hosts
support-report_ip-172-31-33-13_2019-12-19_13-21-27/23-resolv.conf
support-report_ip-172-31-33-13_2019-12-19_13-21-27/25-ntp-config.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/26-initscripts.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/27-packages.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/28-numa.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/29-perfstats.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/30-javainfo.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/31-mysqlinfo.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/32-install-user-limits.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/33-controller-certs.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/34-controller-queries.txt
support-report_ip-172-31-33-13_2019-12-19_13-21-27/controller-configs/
support-report_ip-172-31-33-13_2019-12-19_13-21-27/controller-logs/
support-report_ip-172-31-33-13_2019-12-19_13-21-27/controller-mysql-logs/
support-report_ip-172-31-33-13_2019-12-19_13-21-27/system-logs/

```


## Caveats
Tool requires only bash and some basic system tools. If something is not present - it will just skip collecting information based on this particular tool.

There is still some functionality missing, which hopefuly will be implemented later. All the current issues and 'whish list' is presented on issue list.

Mysql root password - typicaly it is not saved anywhere and must be provided manually by user. Without mysql password, tool will be not able to connect to mysql engine and collect information about database.

Tool is not designed to work on Windows server, only Linux is supported.


## Contributing
Please feel free to file an issue if you think you have found a bug, or if there is a feature you would like to see in this tool.
