Add a file to /etc/netplan named for example 10-monitor.yaml

Replace enp0s8 with the name of your monitoring interface
```console
network:
  ethernets:
    enp0s8:
      dhcp4: false
      optional: true
  version: 2
```

Activate the change
```console
netplan generate
netplan apply
```

Verify that the interface is up
```console
ip link
```
