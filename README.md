## Overview
The Cyber Threat Sensor (CTS) provides in-depth visibility of network-based threats. Network traffic is analyzed by multiple methods based on exclusive NTT techniques and threat intelligence. 
There are two versions of the CTS with different capabilities. The version required depends on the service subscribed to.
* CTS Enhanced: Threat Detection - Enhanced (TD-E) & Managed Detection and Response (MDR) 
* CTS Standard:Security Operations Center as a Service (SOCaaS) 

Capabilities for each version are summarized in the Table 1 below.

| Capability | Enhanced | Standard |
| --- | --- | --- |
| Supported service | TD-E & MDR | SOCaaS |
| Alert and corresponding evidence data (PCAP) sent to SOC Security Analyst for investigation | x | N/A |
| Full PCAP | x | N/A |
| Alert auto-generates Security Incident Report | N/A | x |

Table 1 CTS capabilities

NTT provides specifications for 500 Mbps, 1 Gbps and 4 Gbps throughput.

| CTS throughput | Hardware deployment | Virtual deployment |
| --- | --- | --- |
| 500 Mbps | x | x |
| 1 Gbps | x | x |
| 4 Gbps | x | N/A |

Table 2 Deployment alternatives


## Preparations
Build / configure a host. Bare metal is always the best choice but virtual works when no other options is available.

### Hardware specifications
NTT’s CTS may be run on either virtual or hardware form factors as provisioned by the client.
The specifications varies between CTS - Enhanced and CTS - Standard. Please refer to Table 1 to identify the version that applies to the service(s) you are subscribing to.

### Required Internet access
| Function | Mandatory | Protocol | Port | Destination | Details |
| --- | --- | --- | --- | --- | --- |
| CTS backend | Yes | TCP | 443 | <ul><li>nttsecurity.io (\*.nttsecurity.io, \*.\*.nttsecurity.io)<ul><li>cts.eu1.nttsecurity.io</li><li>metrics.cts.eu1.nttsecurity.io</li></ul></ul> | CTS API backend communication and telemetry |
| Collector backend | Yes | TCP | 443 | <ul><li>samurai-xdr-prod-westeurope-xgliuoit.azure-api.net</li><li>api.westeurope.mdr.security.ntt</li><li>samurai-cts-prod-westeurope.prometheus.rteam.nttsecurity.io</li></ul> | Collector API backend communication and telemetry for Samurai service |
| NTP | Yes | UDP | 123 | customer infrastructure | Time syncronisation |
| DNS | Yes | UDP | 53 | customer infrastructure | Domain name resolution |
| Remote management | No[^1] | TCP | 443 | <ul><li>ra.cto.nttsecurity.io</li><li>deb.releases.teleport.dev</li><li>apt.releases.teleport.dev</li></ul> | Used for remote administration of CTS |
| Container management | Yes | TCP | 443 | <ul><li>docker.com (\*.docker.com)<ul><li>login.docker.com</li><li>hub.docker.com</li><li>download.docker.com</li><li>production.cloudflare.docker.com</li></ul></li><li>docker.io (\*.docker.io)<ul><li>auth.docker.io</li><li>registry-1.docker.io</li></ul></li><li>cdn.auth0.com</li></ul> | Private container registry[^2] |
| Amazon Cloud dependencies | Yes |TCP | 443 | \*.cloudfront.net | Amazon CDN, used by CTS API |
| Payload | Yes | TCP | 443 | \*.s3.\*.amazonaws.com<br>s3.\*.amazonaws.com<br>\*.s3.amazonaws.com<br>s3-w.\*.amazonaws.com<br>\*.blob.core.windows.net | Amazon Cloud Storage and Azure Storage, used to store events and evidence |
| OS updates | Yes | TCP | 80, 443 | <ul><li>ubuntu.com (\*.ubuntu.com)<ul><li>archive.ubuntu.com</li><li>esm.ubuntu.com</li><li>motd.ubuntu.com</li></ul></li></ul> | Ubuntu Software repository |
| Installation | Yes | TCP | 443 | <ul><li>git.io</li><li>raw.githubusercontent.com</li></ul> | Download of installation script |
[^1]: If this access is blocked then NTT will not be able to provide any support or SLA in regards to availability of the service unless a NTTSA are used that can be used for remote management
[^2]: https://docs.docker.com/desktop/allow-list/
#### CTS - Enhanced
##### Virtual deployments
|  | 500 Mbps |1 Gbps  | 4 Gbps |
| --- | --- | --- | --- |
| CPU | 8 cores | 8 cores | N/A |
| Memory | 52 GB RAM<br>(32 GB RAM for OS and 20GB RAM for ramdisk)| 104 GB RAM<br>(64 GB RAM for OS and 40GB RAM for ramdisk) | N/A |
| Disks | System disk: 300GB<br>Dynamic data disk: 200GB|System disk:      300GB<br>Dynamic data disk: 200GB|N/A |
| Network interfaces | Management:1 x 1 Gbit/s<br>Network Monitoring:1 x 1 Gbit/s | Management:1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | N/A |

##### Hardware deployments

|  | 500 Mbps | 1 Gbps | 4 Gbps |
| --- | --- | --- | --- |
| CPU | 1 x Intel Xeon with 16 threads or better | 1 x Intel Xeon with 36 threads or better | 2 x Intel Xeon with 36 threads or better |
| Memory | 32 GB RAM | 64 GB RAM | 128 GB RAM |
| Disks | System disk: 300GB (redundant)<br>Dynamic data disk: 1Tb NVMe | System disk: 300GB (redundant)<br>Dynamic data disk: 2Tb NVMe | System disk: 300GB (redundant)<br>Dynamic data disk: 4Tb NVMe |
| Network interfaces | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s |

#### CTS - Standard
##### Virtual deployments
|  | 500 Mbps | 1 Gbps | 4 Gbps |
| --- | --- | --- | --- |
| CPU | 8 cores | 8 cores | N/A |
| Memory | 32 GB RAM | 40 GB RAM | N/A |
| Disks | System disk: 300GB<br>Dynamic data disk: 200GB | System disk: 300GB<br>Dynamic data disk: 200GB | N/A |
| Network interfaces | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s |

##### Hardware deployments
|  | 500 Mbps | 1 Gbps | 4 Gbps |
| --- | --- | --- | --- |
| CPU | 1 x Intel Core i9 with 8 threads or better | 1 x Intel Core i9 with 8 threads or better | 1 x Intel Xeon with 36 threads or better |
| Memory | 32 GB RAM | 40 GB RAM | 64 GB RAM |
| Disks | System disk: 300GB<br>Dynamic data disk: 200GB | System disk: 300GB<br>Dynamic data disk: 200GB | System disk: 300GB<br>Dynamic data disk: 200GB |
| Network interfaces | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s | Management: 1 x 1 Gbit/s<br>Network Monitoring: 1 x 1 Gbit/s |

### Supported operating systems
* Ubuntu Server 22.04 LTS (x86_64): https://ubuntu.com/download/server

#### Depricated
Still supported for existing deployments but no new installations will be allowed
* CentOS7 7 minimal (x86_64): http://isoredirect.centos.org/centos/7/isos/x86_64/)

### OS installation
Install OS using default settings except for:
* Network: Configure IP address and routing for management interface
* Disk: Partition system disk according to default values. Do NOT modify data disk, leave the data disk untouched. It will be formated by the installer.

### Bring monitoring interface up
Check doc folder in this project and configure your monitoring interface accordingly

### Install the CTS
Issue the following command and follow the guide. Once completed the CTS is ready.
```console
wget -q -O install.sh https://git.io/JZmVM && sudo bash ./install.sh
```
