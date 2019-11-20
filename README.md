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

