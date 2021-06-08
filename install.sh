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
systemctl stop ntpd
ntpdate ${NTP1}
hwclock --systohc
systemctl enable ntpd
systemctl start ntpd
timedatectl set-timezone UTC

# Creating dummy0 interface
# Some AWS instances of CentOS 7 hang during boot, we need a work around for them
TOKEN=$(curl --silent --connect-timeout 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") > /dev/null 2>&1 \
&& curl --silent --connect-timeout 2 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/ > /dev/null 2>&1
if [[ "$?" == "0" ]]; then
  echo "This is most likely an EC2 instance in AWS. Creating dummy0 using rc.local"
  cat <<EOF > /etc/rc.local
modprobe dummy numdummies=1
ip link set name dummy0 dev dummy0
ip link set dummy0 up
EOF
  chmod +x /etc/rc.d/rc.local
  systemctl enable rc-local
  modprobe dummy numdummies=1
  ip link set name dummy0 dev dummy0
  ip link set dummy0 up
else
  echo "Creating dummy0 interface"
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
fi
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
ifaces=$(ls -m /sys/class/net)
while :
  do
    echo "Available interfaces: ${ifaces}"
    read -p "Define monitoring interface: " MONITOR
    if_ok="true"
    OLD_IFS=$IFS
    IFS=","
    for m_interface in $MONITOR
      do
        if [[ " ${ifaces} " != *"${m_interface}"* ]]; then
          echo "${m_interface} does not exists"
          if_ok="false"
        fi
    done
    IFS=$OLD_IFS
    if [[ "$if_ok" == "true" ]] && [[ ${MONITOR} != "" ]] ; then
      break
    fi
done

read -p "Init key: " INITKEY
read -p "Device name: " DEVICENAME

# Initiate CTS
sudo docker run --network host \
                --privileged \
                --rm \
                -e "INITIATOR_ENV=eu1" \
                -e "INIT_KEY=${INITKEY}" \
                -e "DEVICENAME=${DEVICENAME}" \
                -e "INTERFACES=${MONITOR}" \
                -v /:/rootfs \
                -v /var/run/docker.sock:/var/run/docker.sock:rw \
                nttsecurityes/initiator:latest
