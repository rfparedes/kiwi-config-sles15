#!/bin/bash
# Copyright (c) 2015 SUSE LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# 
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

# mkdir /var/lib/named
# mkdir /var/lib/pgsql
# mkdir /var/lib/mailman
# mkdir /boot/grub2/i386-pc

mkdir /var/lib/misc/reconfig_system

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]-[$kiwi_profiles]..."

#======================================
# add missing fonts
#--------------------------------------
CONSOLE_FONT="eurlatgr.psfu"

#======================================
# prepare for setting root pw, timezone
#--------------------------------------
echo ** "reset machine settings"
sed -i 's/^root:[^:]*:/root:$6$hCNSYkKblMHbP4f.$f\/vybdbvihHXs83RcmkWDIkAjHvk.QriNCHfDz2itBJkkCJZDkJmo0QwV8rPkxZKXGOq3uIMzqfIKbsbRVq3U0:/' /etc/shadow
rm /etc/machine-id
rm /etc/localtime
rm /var/lib/zypp/AnonymousUniqueId
rm /var/lib/systemd/random-seed

#=====================================
# Rich customizations
#-------------------------------------
/usr/bin/hostnamectl set-hostname 150golden

#======================================
# SuSEconfig
#--------------------------------------
echo "** Running suseConfig..."
suseConfig

echo "** Running ldconfig..."
/sbin/ldconfig

#======================================
# Setup baseproduct link
#--------------------------------------
suseSetupProduct

#======================================
# Specify default runlevel
#--------------------------------------
baseSetRunlevel 3

#======================================
# Add missing gpg keys to rpm
#--------------------------------------
suseImportBuildKey

#======================================
# Enable DHCP on eth0
#--------------------------------------
cat >/etc/sysconfig/network/ifcfg-eth0 <<EOF
BOOTPROTO='dhcp'
MTU=''
REMOTE_IPADDR=''
STARTMODE='auto'
ETHTOOL_OPTIONS=''
USERCONTROL='no'
EOF

#======================================
# Firewall Configuration
#--------------------------------------
echo '** Configuring firewall...'
chkconfig firewalld on

#======================================
# Enable sshd
#--------------------------------------
chkconfig sshd on

#======================================
# Remove doc files
#--------------------------------------
baseStripDocs

#======================================
# remove rpms defined in config.xml in the image type=delete section 
#--------------------------------------
baseStripRPM

#======================================
# Sysconfig Update
#--------------------------------------
echo '** Update sysconfig entries...'
# baseUpdateSysConfig /etc/sysconfig/snapper SNAPPER_CONFIGS root
if [ "${kiwi_profiles}" != "OpenStack-Cloud" ]; then
	baseUpdateSysConfig /etc/sysconfig/network/dhcp DHCLIENT_SET_HOSTNAME yes
fi

# Systemd controls the console font now
echo FONT="$CONSOLE_FONT" >> /etc/vconsole.conf

#======================================
# SSL Certificates Configuration
#--------------------------------------
echo '** Rehashing SSL Certificates...'
update-ca-certificates

if [ ! -s /var/log/zypper.log ]; then
	> /var/log/zypper.log
fi

#======================================
# Import trusted rpm keys
#--------------------------------------
for i in /usr/lib/rpm/gnupg/keys/gpg-pubkey*asc; do
    # importing can fail if it already exists
    rpm --import $i || true
done

# only for debugging
#systemctl enable debug-shell.service

#=====================================
# Configure snapper
#-------------------------------------
if [ "$kiwi_btrfs_root_is_snapshot" = 'true' ]; then
        echo "creating initial snapper config ..."
        # we can't call snapper here as the .snapshots subvolume
        # already exists and snapper create-config doens't like
        # that.
        cp /etc/snapper/config-templates/default /etc/snapper/configs/root
        # Change configuration to match SLES12-SP1 values
        sed -i -e '/^TIMELINE_CREATE=/s/yes/no/' /etc/snapper/configs/root
        sed -i -e '/^NUMBER_LIMIT=/s/50/10/'     /etc/snapper/configs/root

        baseUpdateSysConfig /etc/sysconfig/snapper SNAPPER_CONFIGS root
fi

#=====================================
# Enable chrony if installed
#-------------------------------------
if [ -f /etc/chrony.conf ]; then
	suseInsertService chronyd
	for i in 0 1 2 3; do
		echo "server $i.opensuse.pool.ntp.org iburst"
	done > /etc/chrony.d/opensuse.conf
fi

#======================================
# Configure system for IceWM usage
#--------------------------------------
# XXX remove explicit RPi mentioning
if [[ "$kiwi_profiles" == *"X11"* ]] || [[ "$kiwi_profiles" == *"RaspberryPi"* ]]; then
	baseUpdateSysConfig /etc/sysconfig/displaymanager DISPLAYMANAGER xdm
	baseUpdateSysConfig /etc/sysconfig/displaymanager DISPLAYMANAGER_STARTS_XSERVER yes
	baseUpdateSysConfig /etc/sysconfig/windowmanager DEFAULT_WM icewm

	# We want to start in gfx mode
	baseSetRunlevel 5
	suseConfig
fi

#======================================
# Disable recommends on virtual images (keep hardware supplements, see bsc#1089498)
#--------------------------------------
if [[ "$kiwi_profiles" != *"RaspberryPi"* ]]; then
	sed -i 's/.*solver.onlyRequires.*/solver.onlyRequires = true/g' /etc/zypp/zypp.conf
fi

#======================================
# Disable installing documentation
#--------------------------------------
sed -i 's/.*rpm.install.excludedocs.*/rpm.install.excludedocs = yes/g' /etc/zypp/zypp.conf

#======================================
# Configure Raspberry Pi specifics
#--------------------------------------
if [[ "$kiwi_profiles" == *"RaspberryPi"* ]]; then
	# Add necessary kernel modules to initrd (will disappear with bsc#1084272)
	echo 'add_drivers+=" bcm2835_dma dwc2 "' > /etc/dracut.conf.d/raspberrypi_modules.conf

	# Work around HDMI connector bug and network issues
  	cat > /etc/modprobe.d/50-rpi3.conf <<-EOF
		# No HDMI hotplug available
		options drm_kms_helper poll=0
		# Prevent too many page allocations (bsc#1012449)
		options smsc95xx turbo_mode=N
	EOF

	cat > /usr/lib/sysctl.d/50-rpi3.conf <<-EOF
		# Avoid running out of DMA pages for smsc95xx (bsc#1012449)
		vm.min_free_kbytes = 2048
	EOF

	# Do network configuration via yast2-firstboot
	rm -f /etc/sysconfig/network/ifcfg-eth0

	# Make sure the netconfig md5 files are correct
	netconfig update -f
fi

##
baseCleanMount

exit 0
