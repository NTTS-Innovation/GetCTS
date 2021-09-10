
# Requirements

Install iftop

## CentOS

```console
sudo yum -y install iftop
```

## Ubuntu

```console
sudo apt -y install iftop
```

# Verify network traffic

Issue iftop using the command below. It will sample data for 60 seconds and show the result with top source and destinations per port/service. If you prefer to see output without resolving ip and service please add -n -N to the command

```console
sudo iftop -p -b -P -t -i enp5s0 -s 60
```

## Example output

```console
interface: enp5s0
MAC address is: <redacted>
Listening on enp5s0
   # Host name (port/service if enabled)            last 2s   last 10s   last 40s cumulative
--------------------------------------------------------------------------------------------
   1 vps-323211c2.vps.ovh.net:http            =>      130Kb      130Kb      133Kb      963KB
     10.30.12.34:50997                        <=     5.08Kb     5.08Kb     5.18Kb     37.6KB
   2 32-12-12-45.vpn.dark-vpn.net:openvpn     =>     7.95Kb     20.7Kb     21.1Kb      145KB
     10.31.12.34:34259                        <=     14.5Kb     24.4Kb     26.1Kb      184KB
   3 ec2-3-12-1-43.eu-central-1.comp:https    =>         0b     6.81Kb     1.70Kb     8.52KB
     cts.home.local:50114                     <=         0b     10.2Kb     2.54Kb     12.7KB
   4 WS-US-FLORIDA-JOE.some.domain:18876      =>         0b     1.47Kb       376b     1.83KB
     c32-12-12-65.broadband.some.domain:https <=         0b     4.92Kb     1.23Kb     6.14KB
   5 WS-US-FLORIDA-JOE.some.domain:18876      =>         0b     1.47Kb       376b     1.83KB
     10.54.13.13:https                        <=         0b     4.92Kb     1.23Kb     6.14KB
   6 desktop-office.home.local:13437          =>         0b     4.47Kb     3.42Kb     24.7KB
     10.31.12.34:9091                         <=         0b       912b     1.44Kb     9.97KB
   7 desktop-office.home.local:1066           =>         0b     1.58Kb     3.02Kb     22.7KB
     10.31.12.34:9091                         <=         0b     1.33Kb     1.11Kb     8.31KB
   8 WS-US-FLORIDA-JOE.some.domain:50700      =>         0b     1.66Kb     1.01Kb     7.68KB
     ec2-54-241-197-58.us-west-1.comput:https <=         0b       268b       184b     1.47KB
   9 40.101.28.194:https                      =>         0b     0.99Kb       255b     1.24KB
     WS-US-FLORIDA-JOE.some.domain:17801      <=         0b        32b         8b        40B
  10 dns.opendns.com:https                    =>         0b       658b       164b       822B
     WS-US-FLORIDA-JOE.some.domain:18878      <=       160b       296b        74b       370B
--------------------------------------------------------------------------------------------
Total send rate:                                         0b         0b         0b
Total receive rate:                                   165Kb      235Kb      363Kb
Total send and receive rate:                          165Kb      235Kb      363Kb
--------------------------------------------------------------------------------------------
Peak rate (sent/received/total):                         0b     1.34Mb     1.34Mb
Cumulative (sent/received/total):                        0B     2.88MB     2.88MB
============================================================================================
```

You should verify that the interface only receive traffic and don't send anything. Monitoring interfaces should be passive unless they are receiving data using erspan or any other "active" method that require IP configuration. 

span and rspan only require the monitoring interface to be up without any ip address assigned.

Verify that you can see traffic from all configured networks. You can also verify one network at the time by adding -F net/mask, example:

```console
sudo iftop -p -b -P -t -i enp5s0 -s 60 -F 10.31.12.0/24
```

# Troubleshooting

## iftop does not stop after 60 seconds

This is a known issue when the interface does not recieve ANY data. Make sure the monitoring interface is connected. If the issue persist then connect another computer to the switch interface and use for example Wireshark to see if there are any traffic

## iftop does not show expected network traffic

It's probably because miss configuration of monitored networks. Verify switch configuration

## iftop reports several Gbit/s but the CTS is only sized for 1 Gbit

Make sure to ignore backend networks such as SAN traffic, hypervisor and backup. They are most likely not as interesting as traffic between server/client - Internet and client <-> server.
