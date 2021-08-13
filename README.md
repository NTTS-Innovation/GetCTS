## Preparations
Build / configure a host. Bare metal is always the best choice but virtual works when no other options is available.

### Hardware specifications
#### 500 Mbit/s
* CPU: 1 x Intel Core i9 with 8 threads
* Memory: 32 Gb RAM
* Disk:
  * System: 300 Gb
  * Dynamic data: 200 Gb
* Network:
  * Management:  1 x 1 Gbit
  * Monitoring: 1 x 1 Gbit

#### 1 Gb/s
* CPU: 1 x core i9 with 8 threads
* Memory: 40 Gb RAM
* Disk:
  * System: 300 Gb
  * Dynamic data: 200 Gb
* Network:
  * Management:  1 x 1 Gbit
  * Monitoring: 1 x 1 Gbit

### OS installation
Install CentOS 7 minimal (x86_64) (http://isoredirect.centos.org/centos/7/isos/x86_64/) on the host. Ubuntu 20.04 will be official supported soon but it works just fine. 

Make sure to leave dynamic data disk untouched in the installer, it must not be formated. Install and partition system disk using default settings and configure management networks for Internet access. 

### Bring monitoring interface up
Check doc folder in this project and configure your monitoring interface accordingly

### Install the CTS
Issue the following command and follow the guide. Once completed the CTS is ready to be assigned to the app by browse to the management IP on http port 80
```console
curl -s -L https://git.io/JZmVM --output install.sh && sudo bash ./install.sh
```
