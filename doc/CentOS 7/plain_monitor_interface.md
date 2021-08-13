Add a file to /etc/sysconfig/network-scripts/ named for example ifcfg-eth1

```console
BOOTPROTO=none
ONBOOT=yes
TYPE=Ethernet
```

Activate the change, replace eth1 with the name of your monitoring interface
```console
sudo systemctl restart network
```

Verify that the interface is up
```console
ip link
```

