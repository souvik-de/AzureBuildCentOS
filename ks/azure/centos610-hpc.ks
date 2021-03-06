# Kickstart for provisioning a CentOS 6.10 Azure HPC VM

# System authorization information
auth --enableshadow --passalgo=sha512

# Use graphical install
text

# Do not run the Setup Agent on first boot
firstboot --disable

# Keyboard layouts
keyboard us

# System language
lang en_US.UTF-8

# Network information
network --bootproto=dhcp

# Use network installation
url --url=http://olcentgbl.trafficmanager.net/centos/6.10/os/x86_64/
repo --name="CentOS-Updates" --baseurl=http://olcentgbl.trafficmanager.net/centos/6.10/updates/x86_64/

# Root password
rootpw --plaintext "to_be_disabled"

# System services
services --enabled="sshd,waagent,ntpd,dnsmasq,hypervkvpd"

# System timezone
timezone Etc/UTC --isUtc

# Partition clearing information
clearpart --all --initlabel

# Clear the MBR
zerombr

# Disk partitioning information
part / --fstype="ext4" --size=1 --grow --asprimary

# System bootloader configuration
bootloader --location=mbr --append="numa=off console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 disable_mtrr_trim" --timeout=1

# Add OpenLogic repo
repo --name=openlogic --baseurl=http://olcentgbl.trafficmanager.net/openlogic/6/openlogic/x86_64/

# Firewall configuration
firewall --disabled

# Enable SELinux
selinux --enforcing

# Don't configure X
skipx

# Power down the machine after install
poweroff

%packages
@base
@console-internet
@core
@debugging
@directory-client
@hardware-monitoring
@java-platform
@large-systems
@network-file-system-client
@performance
@perl-runtime
@server-platform
ntp
dnsmasq
cifs-utils
sudo
python-pyasn1
parted
WALinuxAgent
msft-rdma-drivers
kernel-headers
kernel-devel
libstdc++.i686
redhat-lsb
-hypervkvpd
-hyperv-daemons
-dracut-config-rescue

%end

%post --log=/var/log/anaconda/post-install.log

#!/bin/bash

# Disable the root account
usermod root -p '!!'

# Remove unneeded parameters in grub
sed -i 's/ numa=off//g' /boot/grub/grub.conf
sed -i 's/ rhgb//g' /boot/grub/grub.conf
sed -i 's/ quiet//g' /boot/grub/grub.conf
sed -i 's/ crashkernel=auto//g' /boot/grub/grub.conf

# Set OL repos
curl -so /etc/yum.repos.d/CentOS-Base.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/CentOS-Base.repo
curl -so /etc/yum.repos.d/OpenLogic.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/OpenLogic.repo

# Import CentOS and OpenLogic public keys
curl -so /etc/pki/rpm-gpg/OpenLogic-GPG-KEY https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/OpenLogic-GPG-KEY
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
rpm --import /etc/pki/rpm-gpg/OpenLogic-GPG-KEY

# Enable SSH keepalive
sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

# Changing password retrictions defined by CIS CentOS Linux 6 Benchmark
sudo sed -i 's/pam_cracklib.so try_first_pass retry=3 type=/\pam_cracklib.so try_first_pass retry=3 minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1/g' /etc/pam.d/system-auth

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
PERSISTENT_DHCLIENT=yes
EOF

cat << EOF > /etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

# Disable persistent net rules
touch /etc/udev/rules.d/75-persistent-net-generator.rules
rm -f /lib/udev/rules.d/75-persistent-net-generator.rules /etc/udev/rules.d/70-persistent-net.rules

# Disable some unneeded services by default (administrators can re-enable if desired)
chkconfig cups off

# Enable RDMA driver

  ## Need to pull these packages from latest 6.8 repo
  yum -y install rdma librdmacm libmlx4 dapl libibverbs

  ## Install LIS4.1 with RDMA drivers
  ND="144"
  cd /opt/microsoft/rdma/rhel610
  rpm -i --nopre microsoft-hyper-v-rdma-*.${ND}-*.x86_64.rpm \
                 kmod-microsoft-hyper-v-rdma-*.${ND}-*.x86_64.rpm
  rm -f /initramfs-2.6.32-642.el6.x86_64.img 2>/dev/null
  rm -f /boot/initramfs-2.6.32-642.el6.x86_64.img 2>/dev/null
  echo -e "\nexclude=kernel*\n" >> /etc/yum.conf
  chkconfig rdma on

  ## WALinuxAgent 2.2.x
  sed -i 's/^\#\s*OS.EnableRDMA=.*/OS.EnableRDMA=y/' /etc/waagent.conf

# Need to increase max locked memory
echo -e "\n# Increase max locked memory for RDMA workloads" >> /etc/security/limits.conf
echo '* soft memlock unlimited' >> /etc/security/limits.conf
echo '* hard memlock unlimited' >> /etc/security/limits.conf

# NetworkManager should ignore RDMA interface
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth1
DEVICE=eth1
ONBOOT=no
NM_CONTROLLED=no 
EOF

# Install Intel MPI
MPI="l_mpi-rt_p_5.1.3.223"
CFG="IntelMPI-v5.x-silent.cfg"
curl -so /tmp/${MPI}.tgz http://olcentwus.cloudapp.net/openlogic/${MPI}.tgz  ## Link to MPI package
curl -so /tmp/${CFG} https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/${CFG}
tar -C /tmp -zxf /tmp/${MPI}.tgz
/tmp/${MPI}/install.sh --silent /tmp/${CFG}
rm -rf /tmp/${MPI}* /tmp/${CFG}

# Modify yum, sync history, clean cache
echo "http_caching=packages" >> /etc/yum.conf
yum history sync
yum clean all

# Deprovision and prepare for Azure
/usr/sbin/waagent -force -deprovision

%end
