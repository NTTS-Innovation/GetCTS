#!/bin/bash
# Exit on any error
set -e

MIN_KERNEL_VERSION="3.10.0-1127.8.2.el7.x86_64"
RUNNING_KERNEL_VERSION=$(uname -r)

vercomp() {
  if [[ $1 == $2 ]]; then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i = 0; i < ${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      return 0
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      return 1
    fi
  done
  return 0
}

format_disk() {
  disks=$(lsblk -dpno name | sed -e 's/[^ ]*loop[^ ]*//ig' | xargs)
  unformated_disks=""
  echo ""
  echo "Available disks to partition and format for data storage:"
  for d in $disks; do
    if [[ $(/sbin/sfdisk -d ${d} 2>&1) == "" || $(/sbin/sfdisk -d ${d} 2>&1) == *"does not contain a recognized partition table"* ]]; then
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
  while :; do
    found_disk="no"
    disk=$(reader "Type disk path for partition: " "DATA_DISK_PATH")
    for d in $unformated_disks; do
      if [[ "$d" == "${disk}" ]]; then
        found_disk="yes"
        break
      fi
    done
    if [[ "${found_disk}" != "yes" ]]; then
        echo "${disk} was not found in the list of unformated disks"
    else
        break
    fi
  done
  while :; do
    echo ""
    echo "This is the disk you are about to partition and all data will be deleted"
    fdisk -l $disk
    echo ""
    echo ""
    echo "Are you SURE you want to delete all data on $disk?"
    INPUT=$(reader "Type YES to delete all data and partition $disk: " "DELETE_DATA_DISK")
    if [[ "${INPUT^^}" == "YES" ]]; then
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
    echo "$PARTITION /srv/docker/cts/data ext4 defaults 0 2" >>/etc/fstab
  else
    echo "Mount already exists in /etc/fstab"
  fi
  mount -a
}

function secret_reader() {
  if [ -z ${!2} ]; then
    read -s -p "${1}" ${2}
    echo "${!2}"
  else
    echo "${!2}"
  fi
}

function reader() {
  if [ -z ${!2} ]; then
    read -p "${1}" ${2}
    echo "${!2}"
  else
    echo "${!2}"
  fi
}

install_unattended() {
  while :; do
    INPUT=$(reader "Do you want to enable unattended updates? Type YES or NO: " "CONFIGURE_UNATTENDED_UPDATES")
    if [[ "${INPUT^^}" == "YES" ]]; then
      if [[ "${DIST}" == "ubuntu" ]]; then
        # Uninstall update-notifier-common since unattended-upgrades has the same config file defined and they
        #  can't exist at the same time.
        DEBIAN_FRONTEND=noninteractive apt -y remove update-notifier-common
        DEBIAN_FRONTEND=noninteractive apt -y install unattended-upgrades apt-config-auto-update
        configure_unattended
      elif [[ "${DIST}" == "centos" ]]; then
        yum -y install yum-cron
        configure_unattended
      fi
      break
    fi
    if [[ "${INPUT^^}" == "NO" ]]; then
      break
    fi
  done
}

configure_unattended() {
  if [[ "${DIST}" == "ubuntu" ]]; then
    cat <<EOF >/etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
  "\${distro_id}:\${distro_codename}";
  "\${distro_id}:\${distro_codename}-security";
  "\${distro_id}ESMApps:\${distro_codename}-apps-security";
  "\${distro_id}ESM:\${distro_codename}-infra-security";
  "\${distro_id}:\${distro_codename}-updates";
};
Unattended-Upgrade::Package-Blacklist {
  "linux-headers*";
  "linux-image*";
  "linux-generic*";
  "linux-modules*";
  "docker-ce*";
  "containerd.io";
};
Unattended-Upgrade::DevRelease "auto";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
EOF
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
  elif [[ "${DIST}" == "centos" ]]; then
    cat <<EOF >/etc/yum/yum-cron.conf
[commands]
update_cmd = default
update_messages = yes
download_updates = yes
apply_updates = yes
random_sleep = 360
[emitters]
system_name = None
emit_via = stdio
output_width = 80
[base]
debuglevel = -2
skip_broken = True
mdpolicy = group:main
assumeyes = True
exclude = kernel* container* docker*
EOF
    systemctl enable yum-cron
    systemctl start yum-cron
  fi
}

# Load defaults if they exist
set +e
if [ -f ".defaults" ]; then
  . .defaults
fi

# Load os-release so we know on what dist we are
if [ -f "/etc/os-release" ]; then
  . /etc/os-release
  if [[ "${ID}" == "centos" ]]; then
    if [[ "${VERSION_ID}" == "7" ]]; then
      echo "Supported Linux dist detected: ${ID} ${VERSION_ID}"
      DIST=${ID}
    else
      echo "Unsupported Linux dist detected: ${ID} ${VERSION_ID}, aborting!"
      exit 1
    fi
  elif [[ "${ID}" == "ubuntu" ]]; then
    if [[ "${VERSION_ID}" == "20.04" ]] || [[ "${VERSION_ID}" == "22.04" ]]; then
      echo "Supported Linux dist detected: ${ID} ${VERSION_ID}"
      DIST=${ID}
    else
      echo "Unsupported Linux dist detected: ${ID} ${VERSION_ID}, aborting!"
      exit 1
    fi
  elif [[ "${ID}" == "debian" ]]; then
    if [[ "${VERSION_ID}" == "10" ]]; then
      echo "Supported Linux dist detected: ${ID} ${VERSION_ID}"
      DIST=${ID}
    else
      echo "Unsupported Linux dist detected: ${ID} ${VERSION_ID}, aborting!"
      exit 1
    fi
  fi
else
  echo "/etc/os-release is missing, that should not happend, aborting!"
  exit 1
fi

if (($EUID != 0)); then
  echo "Please execute the script with sudo"
  exit
fi

while :; do
  echo ""
  echo "Type service level of the device, valid service levels are:"
  echo "  'PREPARE' does not initiate the CTS, it will just install and prepare for initiation"
  echo "  J-AUTO"
  echo "  CTS-AI"
  echo "  CTS-E"
  echo "  CTS-S"
  echo "  PREPARE"
  SERVICE_LEVEL=$(reader "Service level: " "SERVICE_LEVEL")
  if [[ "${SERVICE_LEVEL^^}" == "CTS-AI" ]] || [[ "${SERVICE_LEVEL^^}" == "J-AUTO" ]] || [[ "${SERVICE_LEVEL^^}" == "CTS-E" ]] || [[ "${SERVICE_LEVEL^^}" == "CTS-S" ]] || [[ "${SERVICE_LEVEL^^}" == "PREPARE" ]]; then
    break
  fi
  echo "If you want to abort and restart install please press CTRL+C"
  unset SERVICE_LEVEL
done

# Install required packages
if [[ "${DIST}" == "centos" ]]; then
  yum install -y epel-release
  yum install -y ntp yum-plugin-versionlock yum-utils device-mapper-persistent-data lvm2 iftop

elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  apt update
  DEBIAN_FRONTEND=noninteractive apt -y install apt-transport-https ca-certificates curl gnupg lsb-release netplan.io ntpdate iftop systemd-timesyncd parted cron
fi

# Check if /srv/docker/cts/data is a mount
mount_ok="false"
for m_point in /srv /srv/docker /srv/docker/cts /srv/docker/cts/data; do
  mountpoint -q ${m_point}
  if [[ "$?" == "0" ]]; then
    mount_ok="true"
  fi
done
if [[ "$mount_ok" == "false" ]]; then
  echo "/srv/docker/cts/data is not mounted. Please make sure to mount this path to a high performance NVMe disk"
  echo "  with sufficent amount of free space for the calculated amount of recorded network traffic"
  while :; do
    INPUT=$(reader "Do you want this installer to try to find a partition to format for you? Type YES or NO: " "FORMAT_DATA_DISK")
    if [[ "${INPUT^^}" == "YES" ]]; then
      format_disk
      break
    fi
    if [[ "${INPUT^^}" == "NO" ]]; then
      exit 1
    fi
  done
fi
set -e

# Configure repositories
if [[ "${ID}" == "ubuntu" ]] && [[ "${VERSION_ID}" == "22.04" ]]; then
  cat <<EOF >/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu jammy main restricted
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted
deb http://archive.ubuntu.com/ubuntu jammy universe
deb http://archive.ubuntu.com/ubuntu jammy-updates universe
deb http://archive.ubuntu.com/ubuntu jammy multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates multiverse
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-security main restricted
deb http://archive.ubuntu.com/ubuntu jammy-security universe
deb http://archive.ubuntu.com/ubuntu jammy-security multiverse
EOF
fi

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
  apt update
  DEBIAN_FRONTEND=noninteractive apt -y dist-upgrade
fi

# Create support user for NTT
echo ""
while :; do
  INPUT=$(reader "Do you want to create NTT support user (nttsecurity)? Type YES or NO: " "CREATE_SUPPORT_USER")
  if [[ "${INPUT^^}" == "YES" ]]; then
    echo "Please type a temporary password for user nttsecurity and write it down in a secure place"
    echo "This password needs to be distributed to NTT Service transition team for management"
    echo ""
    if [[ "${DIST}" == "centos" ]]; then
      adduser nttsecurity || true
      CREDENTIALS=$(secret_reader "Password: " "SUPPORT_USER_PASSWORD")
      echo ${CREDENTIALS} | passwd nttsecurity --stdin
      usermod -aG wheel nttsecurity
    elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
      adduser --disabled-password --gecos "" nttsecurity || true
      CREDENTIALS=$(secret_reader "Password: " "SUPPORT_USER_PASSWORD")
      echo -e "${CREDENTIALS}\n${CREDENTIALS}" | passwd nttsecurity
      usermod -aG sudo nttsecurity
    fi
    break
  fi
  if [[ "${INPUT^^}" == "NO" ]]; then
    break
  fi
done

if [[ "${SERVICE_LEVEL^^}" == "CTS-E" ]]; then
  echo "Do you want network recorder to store data to the default data storage disk (/srv/docker/cts/data) or do you wish to use a RAM disk?"
  echo "  RAM disk requires at least 40Gb extra ram (minimum 104Gb in total) and should only be used under special circumstances"
  while :; do
    INPUT=$(reader "Type DISK (default) or RAM: " "NETWORK_RECORDER_LOCATION")
    if [[ "${INPUT^^}" == "DISK" ]]; then
      break
    fi
    if [[ "${INPUT^^}" == "RAM" ]]; then
      # Make sure there is more than 104Gb of ram (using decimal)
      AVAILABLE_RAM_KB=$(cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')
      if ((${AVAILABLE_RAM_KB} < 104000000)); then
        echo "RAM disk requires at least 40Gb RAM, minimum 104Gb in total. You have ${AVAILABLE_RAM_KB} kB available."
        echo "  Example: 500 Mbit CTE-E requires at least 64Gb + 40Gb = 104Gb total RAM."
        echo "  Abort using CTRL+C and add more RAM or use DISK instead"
        continue
      fi
      # Create RAM disk for stenotype
      echo ""
      mkdir -p /srv/docker/cts/data/stenographer
      if ! grep "/srv/docker/cts/data/stenographer" /etc/fstab; then
        echo "Adding mount to /etc/fstab"
        echo "tmpfs /srv/docker/cts/data/stenographer tmpfs nodev,nosuid,noexec,nodiratime,size=40960M 0 0" >>/etc/fstab
      else
        echo "Mount already exists in /etc/fstab"
      fi
      mount -a
      break
    fi
  done
fi

# Configure NTP
echo ""
echo "Configure server time"
echo "Leave secondary NTP server empty if you only have one (just press enter)."
echo "  If you need more please modify /etc/ntp.conf after the installation has been completed"
NTP1=$(reader "Primary NTP server: " "NTP1")
NTP2=$(reader "Secondary NTP server: " "NTP2")
if [ "$NTP1" = "" ] && [ "$NTP2" = "" ]; then
  echo "[-] No NTP server specified, defaulting to \"1.ubuntu.pool.ntp.org\""
  NTP1=1.ubuntu.pool.ntp.org
fi
echo ""
if [[ "${DIST}" == "centos" ]]; then
  cat <<EOF >/etc/ntp.conf
driftfile /var/lib/ntp/drift
restrict default nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
disable monitor
server ${NTP1} iburst
EOF
  if [ ! -z ${NTP2} ] && [[ "${NTP2^^}" != "NONE" ]]; then
    echo "server ${NTP2} iburst" >>/etc/ntp.conf
  fi
  systemctl stop ntpd
  ntpdate ${NTP1}
  hwclock --systohc
  systemctl enable ntpd
  systemctl start ntpd
  timedatectl set-timezone UTC
elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
  mkdir -p /etc/systemd/timesyncd.conf.d/
  cat <<EOF >/etc/systemd/timesyncd.conf.d/cts.conf
[Time]
NTP=${NTP1}
EOF
  if [ ! -z ${NTP2} ] && [[ "${NTP2^^}" != "NONE" ]]; then
    echo "FallbackNTP=${NTP2}" >>/etc/systemd/timesyncd.conf.d/cts.conf
  fi
  systemctl stop systemd-timesyncd
  ntpdate ${NTP1}
  hwclock --systohc
  systemctl enable systemd-timesyncd
  systemctl start systemd-timesyncd
  timedatectl set-timezone UTC
fi

# Enable unattended updates if the user wants it
install_unattended

# Creating dummy0 interface
if [[ "${DIST}" == "centos" ]]; then
  # Some AWS instances of CentOS 7 hang during boot, we need a work around for them
  TOKEN=$(curl --silent --connect-timeout 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") >/dev/null 2>&1 &&
    curl --silent --connect-timeout 2 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1
  if [[ "$?" == "0" ]] && [[ ! ${TOKEN} == *"ERR_CONNECT_FAIL"* ]]; then
    echo "This is most likely an EC2 instance in AWS. Creating dummy0 using rc.local"
    cat <<EOF >/etc/rc.local
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
    cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-dummy0
DEVICE=dummy0
NM_CONTROLLED=no
ONBOOT=yes
TYPE=Ethernet
EOF
    echo "dummy" >/etc/modules-load.d/dummy.conf
    echo "options dummy numdummies=1" >/etc/modprobe.d/dummy.conf
    modprobe -v dummy numdummies=1
    ip link set up dummy0
  fi
### DISABLED dummy0 interface for debian/ubuntu. Janitor will start it for now
###  netplan does NOT support dummy interface, the config below does NOT work
#elif [[ "${DIST}" == "debian" ]] || [[ "${DIST}" == "ubuntu" ]]; then
#  echo "Creating dummy0 interface"
#  cat <<EOF >/etc/netplan/10-cts-dummy0.yaml
#network:
#  bridges:
#    dummy0:
#      optional: true
#      dhcp4: false
#EOF
#  netplan generate
#  netplan apply
#  echo "Sleeping for 10 seconds to make sure all interfaces has been reloaded"
#  sleep 10
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
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  apt -y update
  DEBIAN_FRONTEND=noninteractive apt -y install docker-ce docker-ce-cli containerd.io
fi
systemctl enable docker
systemctl start docker

# Show all interfaces, this will be used for last step of enrolling the CTS
ifaces=$(ls -m /sys/class/net)
while :; do
  echo ""
  echo "Available interfaces: ${ifaces}"
  echo "  Use one or more, separated by ','"
  MONITOR=$(reader "Monitoring interface(s): " "MONITORING_INTERFACE")
  if_ok="true"
  OLD_IFS=$IFS
  IFS=","
  for m_interface in $MONITOR; do
    if [[ " ${ifaces} " != *"${m_interface}"* ]]; then
      echo "${m_interface} does not exists"
      if_ok="false"
    fi
  done
  IFS=$OLD_IFS
  if [[ "$if_ok" == "true" ]] && [[ ${MONITOR} != "" ]]; then
    break
  fi
done
# Enroll to custom environment
if [ ! -z ${CUSTOM_ENVIRONMENT} ]; then
  env_string="-e INITIATOR_ENV=${CUSTOM_ENVIRONMENT}"
fi

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

if [[ "${SERVICE_LEVEL^^}" == "CTS-E" ]] || [[ "${SERVICE_LEVEL^^}" == "J-AUTO" ]] || [[ "${SERVICE_LEVEL^^}" == "CTS-S" ]]; then
  echo ""
  echo "Please enter device details. Both init key and device name need to be defined."
  echo "  You should be able to find this information in your enrolment documentation."
  INITKEY=$(reader "Init key: " "INITKEY")
  DEVICENAME=$(reader "Device name: " "DEVICENAME")
  # Initiate CTS-E
  docker run --network host \
    --privileged \
    --rm \
    -e "INIT_KEY=${INITKEY}" \
    -e "DEVICENAME=${DEVICENAME}" \
    -e "INTERFACES=${MONITOR}" \
    ${http_proxy_string}${https_proxy_string}${HTTP_PROXY_STRING}${HTTPS_PROXY_STRING} \
    ${env_string} \
    -v /:/rootfs \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    nttsecurityes/initiator:latest
elif [[ "${SERVICE_LEVEL^^}" == "CTS-AI" ]]; then
  # Initiate CTS-AI
  if [[ "${DIST}" == "centos" ]]; then
    echo "CentOS 7 default firewall policy blocks access to HTTP services. You need temporary access to HTTP during enrolment."
    while :; do
      INPUT=$(reader "Do you want this installer to temporary allow HTTP servies? Type YES or NO: " "ALLOW_HTTP")
      if [[ "${INPUT^^}" == "YES" ]]; then
        firewall-cmd --add-service=http
        echo "Important! You need to open HTTP manually if you restart the appliance before successful enrolment."
        echo "  Issue the following command to temporary open for HTTP:"
        echo "  firewall-cmd --add-service=http"
        break
      fi
      if [[ "${INPUT^^}" == "NO" ]]; then
        echo "WARNING! You did not open for HTTP. The enrolment web page will not be available."
        echo "  Issue the following command to temporary open for HTTP:"
        echo "  firewall-cmd --add-service=http"
        break
      fi
    done
  fi
  docker run --network host \
    --privileged \
    --rm \
    -e "INTERFACES=${MONITOR}" \
    ${http_proxy_string}${https_proxy_string}${HTTP_PROXY_STRING}${HTTPS_PROXY_STRING} \
    ${env_string} \
    -v /:/rootfs \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    nttsecurityes/initiator:latest
else
  # Just prepare for initiation
  echo ""
  echo "This instance has been prepared to initiate an CTS. You need to manually execute initiation command or rerun this script and select another service to complete the enrolment"
  echo "Example command to enroll CTS-AI:"
  echo "  sudo docker run --network host --privileged --rm -e "INTERFACES=${MONITOR}" ${http_proxy_string}${https_proxy_string}${HTTP_PROXY_STRING}${HTTPS_PROXY_STRING} ${env_string} -v /:/rootfs -v /var/run/docker.sock:/var/run/docker.sock:rw nttsecurityes/initiator:latest" | xargs
fi
