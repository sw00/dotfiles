#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

apt-get update 
apt-get install -yq \
   etckeeper \
   software-properties-common \
   psmisc \
   mosh

etckeeper init

add-apt-repository -y ppa:jgmath2000/et
apt-get install -yq et

sed -i 's/#Port 22/Port 7022/g' /etc/ssh/sshd_config
systemctl restart sshd
