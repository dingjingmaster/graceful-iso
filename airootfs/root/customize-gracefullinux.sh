#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -e -u

# Warning: customize_airootfs.sh is deprecated! Support for it will be removed in a future archiso version.

# 设定local
sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
sed -i 's/#\(zh_CN\.UTF-8\)/\1/' /etc/locale.gen
sed -i 's/#\(zh_CN\.GBK\)/\1/' /etc/locale.gen
sed -i 's/#\(zh_CN\.GB2312\)/\1/' /etc/locale.gen
locale-gen

# 设置默认环境
[[ ! -d /etc/default/ ]] && mkdir /etc/default 
cat > /etc/default/locale << EOF
LANG=zh_CN.UTF-8
LC_ADDRESS=zh_CN.UTF-8
LC_IDENTIFICATION=zh_CN.UTF-8
LC_MEASUREMENT=zh_CN.UTF-8
LC_MONETARY=zh_CN.UTF-8
LC_NAME=zh_CN.UTF-8
LC_NUMERIC=zh_CN.UTF-8
LC_PAPER=zh_CN.UTF-8
LC_TELEPHONE=zh_CN.UTF-8
LC_TIME=zh_CN.UTF-8
EOF

# 设置默认以图形启动
systemctl set-default graphical.target
systemctl enable gdm.service


sed -i "s/#Server/Server/g" /etc/pacman.d/mirrorlist
