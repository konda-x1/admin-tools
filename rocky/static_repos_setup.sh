#!/bin/bash

# Sets up rocky, epel, and powertools repositories, and uses static mirror URLs rather than mirror lists.

set -e

ROCKY_MIRROR_BASE='http://dl.rockylinux.org/'
EPEL_MIRROR_BASE='https://download.example/pub/epel/'

sed "s;^mirrorlist=;#mirrorlist=;; s;^#baseurl=.*dl.rockylinux.org/;baseurl=$ROCKY_MIRROR_BASE;" /etc/yum.repos.d/Rocky-*.repo
dnf config-manager --set-enabled powertools
dnf update -y
dnf install -y epel-release
crb enable
sed -i "s;^metalink=;#metalink=;; s;^#baseurl=.*download.example/pub/epel/;baseurl=$EPEL_MIRROR_BASE;" /etc/yum.repos.d/epel*.repo
dnf update -y

