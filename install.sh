#!/bin/bash

# Update system and kernel
echo "Updating operating system and kernel"
yum clean all && yum -y update && yum -y update kernel

# Create support user for NTT
echo ""
echo "Creating NTTSecurity support user"
adduser NTTSecurity
echo "Please type a temporary password for user NTTSecurity and write it down in a secure place"
echo "This password needs to be distributed to NTT Service transition team for management"
echo ""
read -s -p "Password: " CREDENTIALS
echo ${CREDENTIALS} | passwd NTTSecurity --stdin
usermod -aG wheel NTTSecurity

# Install and configure NTP
yum install -y ntp
echo ""
read -p "Primary NTP server: " NTP1
echo "Secondary NTP server, leave empty if you only have one. If you need more please modify /etc/ntp.conf after the installer has been completed"
echo ""
read -p  "Secondary NTP server: " NTP2
ntpdate ${NTP1}
hwclock --systohc
cat <<EOF > /etc/ntp.conf
driftfile /var/lib/ntp/drift
restrict default nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
disable monitor
server ${NTP1} iburst
EOF
if [ ! -z ${NTP2+x} ];then
  echo "server ${NTP2} iburst" >> /etc/ntp.conf
fi
systemctl enable ntpd
systemctl start ntpd
timedatectl set-timezone UTC

# Creating dummy0 interface
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-dummy0
DEVICE=dummy0
NM_CONTROLLED=no
ONBOOT=yes
TYPE=Ethernet
EOF
echo "dummy" > /etc/modules-load.d/dummy.conf
echo "options dummy numdummies=1" > /etc/modprobe.d/dummy.conf
modprobe -v dummy numdummies=1
ifconfig dummy0 up

# Install Docker
echo ""
echo "Removing unvanted packages, error messages may occur"
sudo yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine

yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2

yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

yum install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker

# Show all interfaces, this will be used for last step of enrolling the CTS
echo ""
echo "Define one or more monitoring interfaces using a comma separated list"
echo "Example: eth1,eth2"
echo "Example: eth2"
cat /proc/net/dev
echo ""
read -p "Monitoring interface(s): " INTERFACES

read -p "Init key: " INITKEY
read -p "Device name: " DEVICENAME

# Initiate CTS
sudo docker run --network host \
                --privileged \
                --rm \
                -e 'INITIATOR_ENV=eu1' \
                -e 'INIT_KEY=${INITKEY}' \
                -e 'DEVICENAME=${DEVICENAME}' \
                -e 'INTERFACES=${INTERFACES}' \
                -v /:/rootfs \
                -v /var/run/docker.sock:/var/run/docker.sock:rw \
                nttsecurityes/initiator:latest
