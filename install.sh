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
  echo ""
  echo "Available disks to partition and format for data storage:"
  for d in $disks
    do
      if [[ $(/sbin/sfdisk -d ${d} 2>&1) == ""  || $(/sbin/sfdisk -d ${d} 2>&1) == *"does not contain a recognized partition table"* ]]; then
        echo "  $d"
        unformated_disks="$d $unformated_disks"
      fi
  done
  echo ""
  if [[ ${unformated_disks} == "" ]]; then
    echo "No unformated disks for data storage were found. Please add an unpartitioned disk and"
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
          echo "${disk} is not empty. Please select a disk from the list above"
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
  PARTITION=$(sfdisk -d ${disk} | egrep 'Id=83|type=83' | awk '{print $1}')
  mkfs.ext4 $PARTITION
  mkdir -p /srv/docker/cts/data
  if ! grep "/srv/docker/cts/data" /etc/fstab; then
    echo "Adding mount to /etc/fstab"
    echo "$PARTITION /srv/docker/cts/data ext4 defaults 0 2" >> /etc/fstab
  else
    echo "Mount already exists in /etc/fstab"
  fi
  mount -a
}

# Load os-release so we know on what dist we are
if [ -f "/etc/os-release" ]; then
  . /etc/os-release
  if [[ "${ID}" == "centos" ]] || [[ "${ID}" == "ubuntu" ]] || [[ "${ID}" == "debian" ]]; then
      echo "Supported Linux dist detected: ${ID}"
      DIST=${ID}
  else
      echo "Unsupported Linux dist detected: ${ID}, aborting!"
      clean
      exit 1
  fi
else
  echo "/etc/os-release is missing, that should not happend, aborting!"
  clean
  exit 1
fi

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
if [[ "${DIST}" == "centos" ]]; then
  yum clean all && yum -y update && yum -y update kernel
  if ! vercomp ${MIN_KERNEL_VERSION} ${RUNNING_KERNEL_VERSION}; then
    echo "Running Kernel version is too old and the system was just updated to latest version"
    echo "Please reboot and run this command again"
    exit 1
  fi
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  apt update && apt -y dist-upgrade
fi

# Create support user for NTT
echo ""
echo "Creating nttsecurity support user"
adduser nttsecurity || true
echo "Please type a temporary password for user nttsecurity and write it down in a secure place"
echo "This password needs to be distributed to NTT Service transition team for management"
echo ""
read -s -p "Password: " CREDENTIALS
if [[ "${DIST}" == "centos" ]]; then
  echo ${CREDENTIALS} | passwd nttsecurity --stdin
  usermod -aG wheel nttsecurity
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  usermod -aG sudo nttsecurity
fi

# Install required packages
if [[ "${DIST}" == "centos" ]]; then
  yum install -y ntp yum-plugin-versionlock yum-utils device-mapper-persistent-data lvm2
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  apt -y install apt-transport-https ca-certificates curl gnupg lsb-release ntp netplan.io ntpdate
fi

# Configure NTP
echo ""
echo "Configure server time"
echo "Leave secondary NTP server empty if you only have one (just press enter)."
echo "  If you need more please modify /etc/ntp.conf after the installation has been completed"
read -p "Primary NTP server: " NTP1
read -p "Secondary NTP server: " NTP2
echo ""
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
if [[ "${DIST}" == "centos" ]]; then
  systemctl stop ntpd
  ntpdate ${NTP1}
  hwclock --systohc
  systemctl enable ntpd
  systemctl start ntpd
  timedatectl set-timezone UTC
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  systemctl stop ntp
  ntpdate ${NTP1}
  hwclock --systohc
  systemctl enable ntp
  systemctl start ntp
  timedatectl set-timezone UTC
fi

# Creating dummy0 interface
if [[ "${DIST}" == "centos" ]]; then
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
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  echo "Creating dummy0 interface"
  cat <<EOF > /etc/netplan/10-cts-dummy0.yaml
network:
  bridges:
    dummy0:
      optional: true
      dhcp4: false
EOF
  netplan generate
  netplan apply
  echo "Sleeping for 10 seconds to make sure all interfaces has been reloaded"
  sleep 10
fi
# Install Docker
echo ""
echo "Removing unwanted packages, error messages may occur"
if [[ "${DIST}" == "centos" ]]; then
  yum -y remove docker \
                docker-client \
                docker-client-latest \
                docker-common \
                docker-latest \
                docker-latest-logrotate \
                docker-logrotate \
                docker-engine
  yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
  yum install -y docker-ce docker-ce-cli containerd.io
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  dpkg --remove docker docker-engine docker.io containerd runc
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  apt -y update
  apt -y install docker-ce docker-ce-cli containerd.io
fi
systemctl enable docker
systemctl start docker

# Show all interfaces, this will be used for last step of enrolling the CTS
ifaces=$(ls -m /sys/class/net)
while :
  do
    echo ""
    echo "Available interfaces: ${ifaces}"
    echo "  Use one or more, separated by ','"
    read -p "Monitoring interface(s): " MONITOR
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
if [ ! -z ${http_proxy} ]; then
  http_proxy_string="-e http_proxy=${http_proxy} "
fi
if [ ! -z ${https_proxy} ]; then
  https_proxy_string="-e https_proxy=${https_proxy} "
fi
if [ ! -z ${HTTP_PROXY} ]; then
  HTTP_PROXY_STRING="-e HTTP_PROXY=${HTTP_PROXY} "
fi
if [ ! -z ${HTTPS_PROXY} ]; then
  HTTPS_PROXY_STRING="-e HTTPS_PROXY=${HTTPS_PROXY} "
fi

docker run ${http_proxy_string}${https_proxy_string}--entrypoint /bin/bash -it nttsecurityes/initiator:latest /usr/local/bin/check_internet_access
if [[ "$?" == "1" ]]; then
  echo "Issues with internet access to required resources were found!"
  echo "  Please re run the test until all tests PASS"
  echo "docker run ${http_proxy_string}${https_proxy_string}--entrypoint /bin/bash -it nttsecurityes/initiator:latest /usr/local/bin/check_internet_access"
  exit 1
fi

echo ""
echo "Please enter device details. Both init key and device name need to be defined."
echo "  You should be able to find this information in your enrollment documentation."
read -p "Init key: " INITKEY
read -p "Device name: " DEVICENAME

# Initiate CTS
docker run --network host \
                --privileged \
                --rm \
                -e "INITIATOR_ENV=eu1" \
                -e "INIT_KEY=${INITKEY}" \
                -e "DEVICENAME=${DEVICENAME}" \
                -e "INTERFACES=${MONITOR}" \
                ${http_proxy_string}${https_proxy_string}${HTTP_PROXY_STRING}${HTTPS_PROXY_STRING} \
                -v /:/rootfs \
                -v /var/run/docker.sock:/var/run/docker.sock:rw \
                nttsecurityes/initiator:latest
