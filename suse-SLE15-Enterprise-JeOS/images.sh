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

test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

if [ "${kiwi_profiles}" = "OpenStack-Cloud" ]; then
	# not useful for cloud
	systemctl mask systemd-firstboot.service

	suseInsertService cloud-init-local
	suseInsertService cloud-init
	suseInsertService cloud-config
	suseInsertService cloud-final

	echo '*** adjusting cloud.cfg for openstack'
	sed -i -e '/mount_default_fields/{adatasource_list: [ NoCloud, OpenStack, None ]
	}' /etc/cloud/cloud.cfg
elif [ -f "/etc/YaST2/firstboot.xml" ]; then
	# prefer yast2-firstboot over jeos-firstboot and systemd-firstboot
	systemctl mask systemd-firstboot.service
	suseInsertService cloud-init-local
        suseInsertService cloud-init
        suseInsertService cloud-config
        suseInsertService cloud-final
	touch /var/lib/YaST2/reconfig_system
	# Allow for modified firstboot flow
	if [ -f /etc/YaST2/firstboot-rpi3.xml ]; then
		baseUpdateSysConfig /etc/sysconfig/firstboot FIRSTBOOT_CONTROL_FILE /etc/YaST2/firstboot-rpi3.xml
	fi
	# Make systemd-localed happy
	echo 'LANG=en_US.UTF-8' > /etc/locale.conf
else
	# use jeos-firstboot.service instead of systemd-firstboot.service
	systemctl mask systemd-firstboot.service
	suseInsertService cloud-init-local
        suseInsertService cloud-init
        suseInsertService cloud-config
        suseInsertService cloud-final
fi
