#!/bin/bash
# Exit on any error
set -e

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
        if [[ "${VERSION_ID}" == "22.04" ]]; then
          DEBIAN_FRONTEND=noninteractive apt -y install unattended-upgrades apt-config-auto-update
        else
          # Ubuntu 24.04 does not have apt-config-auto-update
          DEBIAN_FRONTEND=noninteractive apt -y install unattended-upgrades
        fi
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
  "teleport";
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
  if [[ "${ID}" == "ubuntu" ]]; then
    if [[ "${VERSION_ID}" == "22.04" ]] || [[ "${VERSION_ID}" == "24.04" ]]; then
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
apt update
DEBIAN_FRONTEND=noninteractive apt -y install apt-transport-https ca-certificates curl gnupg lsb-release netplan.io ntpdate iftop systemd-timesyncd parted cron

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

if [[ "${ID}" == "ubuntu" ]] && [[ "${VERSION_ID}" == "24.04" ]]; then
  cat <<EOF >/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu noble main restricted
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted
deb http://archive.ubuntu.com/ubuntu noble universe
deb http://archive.ubuntu.com/ubuntu noble-updates universe
deb http://archive.ubuntu.com/ubuntu noble multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-security main restricted
deb http://archive.ubuntu.com/ubuntu noble-security universe
deb http://archive.ubuntu.com/ubuntu noble-security multiverse
EOF
fi

# Update system and kernel
echo "Updating operating system and kernel"
apt update
DEBIAN_FRONTEND=noninteractive apt -y dist-upgrade

# Create support user for NTT
echo ""
while :; do
  INPUT=$(reader "Do you want to create NTT support user (nttsecurity)? Type YES or NO: " "CREATE_SUPPORT_USER")
  if [[ "${INPUT^^}" == "YES" ]]; then
    echo "Please type a temporary password for user nttsecurity and write it down in a secure place"
    echo "This password needs to be distributed to NTT Service transition team for management"
    echo ""
    adduser --disabled-password --gecos "" nttsecurity || true
    CREDENTIALS=$(secret_reader "Password: " "SUPPORT_USER_PASSWORD")
    echo -e "${CREDENTIALS}\n${CREDENTIALS}" | passwd nttsecurity
    usermod -aG sudo nttsecurity
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
timedatectl --adjust-system-clock
systemctl enable systemd-timesyncd
systemctl start systemd-timesyncd
timedatectl set-timezone UTC

# Enable unattended updates if the user wants it
install_unattended

# Install Docker
echo ""
echo "Removing unwanted packages, error messages may occur"
dpkg --remove docker docker-engine docker.io containerd runc
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
apt -y update
DEBIAN_FRONTEND=noninteractive apt -y install docker-ce docker-ce-cli containerd.io
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
