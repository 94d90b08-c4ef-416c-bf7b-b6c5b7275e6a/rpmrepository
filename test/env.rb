#!/usr/bin/env ruby

#Require main file
require_relative '../lib/rpm'

#URI set to test RPM module functionality
REMOTE_URIS = [
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/389-ds-base-devel-1.2.11.15-89.el6.i686.rpm',
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/ConsoleKit-devel-0.4.1-6.el6.x86_64.rpm',
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/ElectricFence-2.2.2-28.el6.x86_64.rpm',
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/GConf2-gtk-2.28.0-7.el6.x86_64.rpm',
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/NetworkManager-devel-0.8.1-113.el6.i686.rpm',
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/OpenEXR-1.6.1-8.1.el6.x86_64.rpm',
    'http://mirror.centos.org/centos/6/os/x86_64/Packages/OpenIPMI-libs-2.0.16-14.el6.x86_64.rpm']
#Butt:
#  - do NOT use less than 7 URIs
#  - some constants hardcoded, but should not
