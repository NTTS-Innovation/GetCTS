Add a file to /etc/sysconfig/network-scripts/ named for example ifcfg-eth1

```console
BOOTPROTO=none
ONBOOT=yes
TYPE=Ethernet
```

Activate the change, you might have to restart your server in some cases.
```console
sudo systemctl restart network
```

Verify that the interface is up
```console
ip link
```

