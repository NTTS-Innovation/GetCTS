It's possible to monitor a subset of all vlan on a trunk using bridge interface. 

Add all VLAN to the bridge and use the bridge interface as monitoring interface

## Configuration
### Install dependensies
```console
yum install -y bridge-utils
```
 
### Verify bridge module
Bridge should already exist, check by issuing the following command
```console
modinfo bridge
```
 Expected output similar to this
 ```console
 [root@localhost modules-load.d]# modinfo bridge
filename:       /lib/modules/3.10.0-1160.36.2.el7.x86_64/kernel/net/bridge/bridge.ko.xz
alias:          rtnl-link-bridge
version:        2.3
license:        GPL
retpoline:      Y
rhelversion:    7.9
srcversion:     9FCAFBF712E396E1F7BFC67
depends:        stp,llc
intree:         Y
vermagic:       3.10.0-1160.36.2.el7.x86_64 SMP mod_unload modversions
signer:         CentOS Linux kernel signing key
sig_key:        82:75:AC:97:31:94:A2:B1:1E:2F:AC:7A:13:D7:C6:54:D9:A4:28:11
sig_hashalgo:   sha256
```

### Add vlan kernel module
Add the following to /etc/modules-load.d/vlan.conf
```console
8021q
```
Load the module manually or reboot the machine
```console
modprobe --first-time 8021q
```

### Add bridge interface
Add the following to /etc/sysconfig/network-scripts/ifcfg-virbr0
```console
DEVICE=virbr0
BOOTPROTO=none
ONBOOT=yes
TYPE=Bridge
NM_CONTROLLED=no
```

### Configure trunk interface
Add the following to /etc/sysconfig/network-scripts/ifcfg-INTERFACE
Example: /etc/sysconfig/network-scripts/ifcfg-enp0s8
```console
BOOTPROTO=none
ONBOOT=yes
TYPE=Ethernet
DEVICE=enp0s8
NM_CONTROLLED=no
```

### Add one or more vlan interfaces to trunk interface
Replace INTERFACE with the trunk interface and VLANID with the id of the vlan
Add the following to /etc/sysconfig/network-scripts/ifcfg-INTERFACE.VLANID
Example: /etc/sysconfig/network-scripts/ifcfg-enp0s8.400
```console
BOOTPROTO=none
ONBOOT=yes
TYPE=VLAN
VLAN=yes
DEVICE=enp0s8.400
BRIDGE=virbr0
NM_CONTROLLED=no
```

### Reboot to make sure changes are persistant
```console
reboot
```

### Verify
Check with brctl that virbr0 has correct member interfaces
```console
[root@localhost network-scripts]# brctl show
bridge name     bridge id               STP enabled     interfaces
docker0         8000.0242b9a0a2f4       no
virbr0          8000.08002704fc76       no              enp0s8.400
                                                        enp0s8.401
                                                        enp0s8.402
                                                        enp0s8.403
                                                        enp0s8.404
                                                        enp0s8.405
                                                        enp0s8.406
                                                        enp0s8.407
                                                        enp0s8.408
                                                        enp0s8.409
[root@localhost network-scripts]#
```
