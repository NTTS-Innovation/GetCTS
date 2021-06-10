#!/bin/bash
# Exit on any error
set -e

MIN_KERNEL_VERSION="3.10.0-1127.8.2.el7.x86_64"
RUNNING_KERNEL_VERSION=$(uname -r)

vercomp () {
  if [[ $1 == $2 ]]
  then
      return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
  do
      ver1[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++))
  do
      if [[ -z ${ver2[i]} ]]
      then
          # fill empty fields in ver2 with zeros
          ver2[i]=0
      fi
      if ((10#${ver1[i]} > 10#${ver2[i]}))
      then
          return 0
      fi
      if ((10#${ver1[i]} < 10#${ver2[i]}))
      then
          return 1
      fi
  done
  return 0
}

format_disk() {
  disks=$(lsblk -dpno name)
  unformated_disks=""
  for d in $disks
    do
      if [[ $(/sbin/sfdisk -d ${d} 2>&1) == "" ]]; then
        echo "Device $d is not partitioned"
        unformated_disks="$d $unformated_disks"
      fi
  done
  echo ""
  if [[ ${unformated_disks} == "" ]]; then
    echo "No unformated disks for data storage was found. Please add a unpartitioned disk and"
    echo "  start this installer again. Aborting..."
    exit 1
  fi
  while :
    do
      read -p "Type disk path for partition: " disk
      if [[ "${disks}" != *"${disk}"* ]]; then
        echo "${disk} was not found!, please type from list above"
      else
        if [[ "${unformated_disks}" != *"${disk}"* ]]; then
          echo "${disk} is not empty. Remove all partitions and start this installer again."
          exit 1
        else
          break
        fi
      fi
  done
  while :
    do
      echo ""
      echo "This is the disk you are about to partition and all data will be deleted"
      fdisk -l $disk
      echo ""
      echo ""
      echo "Are you SURE you want to delete all data on $disk?"
      read -p "Type YES to delete all data and partition $disk: " INPUT
      if [[ "${INPUT}" == "YES" ]]; then
        break
      fi
      echo "If you want to abort and restart install please press CTRL+C"
  done
  parted $disk --script mklabel msdos
  parted $disk --script mkpart primary ext4 0% 100%
  PARTITION=$(sfdisk -d ${disk} |grep Id=83|awk '{print $1}')
  mkfs.ext4 $PARTITION
  mkdir -p /srv/docker/cts/data
  if ! grep "/srv/docker/cts/data" /etc/fstab; then
    echo "Adding mount to /etc/fstab"
    echo "$PARTITION /srv/docker/cts/data ext4 defaults 0 2" >> /etc/fstab
  else
    echo "Mount already exist in /etc/fstab"
  fi
  mount -a
}

# Check if /srv/docker/cts/data is a mount
set +e
mount_ok="false"
for m_point in /srv /srv/docker /srv/docker/cts /srv/docker/cts/data
  do
    mountpoint -q ${m_point}
    if [[ "$?" == "0" ]]; then
      mount_ok="true"
    fi
done
if [[ "$mount_ok" == "false" ]]; then
  echo "/srv/docker/cts/data is not mounted. Please make sure to mount this path to a high performance NVMe disk"
  echo "  with sufficent amount of free space for the calculated amount of recorded network traffic"
  while :
    do
      read -p "Do you want this installer to try to find a partition to format for you? Type YES or NO: " INPUT
      if [[ "${INPUT}" == "YES" ]]; then
        format_disk
        break
      fi
      if [[ "${INPUT}" == "NO" ]]; then
        exit 1
      fi
  done
fi
set -e

# Update system and kernel
echo "Updating operating system and kernel"
yum clean all && yum -y update && yum -y update kernel

if ! vercomp ${MIN_KERNEL_VERSION} ${RUNNING_KERNEL_VERSION}; then
  echo "Running Kernel version is too old and the system was just updated to latest version"
  echo "Please reboot and run this command again"
  exit 1
fi

# Create support user for NTT
echo ""
echo "Creating NTTSecurity support user"
adduser NTTSecurity || true
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
if [ ! -z ${NTP2} ];then
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
if [[ "$?" == "0" ]] && [[ ! ${TOKEN} == *"ERR_CONNECT_FAIL"* ]]; then
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
  ip link set up dummy0
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

# Test connectivity
echo ""
echo "Verifying Internet access to required resources"
if [ ! -z http_proxy ]; then
  http_proxy_string="-e http_proxy=${http_proxy}"
fi
if [ ! -z https_proxy ]; then
  https_proxy_string="-e https_proxy=${https_proxy}"
fi
if [ ! -z HTTP_PROXY ]; then
  HTTP_PROXY_STRING="-e HTTP_PROXY=${HTTP_PROXY}"
fi
if [ ! -z HTTPS_PROXY ]; then
  HTTPS_PROXY_STRING="-e HTTPS_PROXY=${HTTPS_PROXY}"
fi


docker run ${http_proxy_string} ${https_proxy_string} --entrypoint /bin/bash -it nttsecurityes/initiator:latest /usr/local/bin/check_internet_access
if [[ "$?" == "1" ]]; then
  echo "Issues with internet access to required resources was found!"
  echo "  Please re run the test until all tests PASS"
  echo "docker run --entrypoint check_internet_access -it nttsecurityes/initiator:latest"
  exit 1
fi

echo ""
echo "Please enter device details. Both init key and device name needs to be defined."
echo "  You should be able to find this information in your enrollment documentation."
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
                ${http_proxy_string} ${https_proxy_string} ${HTTP_PROXY_STRING} ${HTTPS_PROXY_STRING} \
                -v /:/rootfs \
                -v /var/run/docker.sock:/var/run/docker.sock:rw \
                nttsecurityes/initiator:latest
