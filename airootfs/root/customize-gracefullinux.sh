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

# 设置 dock
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
gsettings set org.gnome.shell.extensions.dash-to-dock show-favorites true
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
gsettings set org.gnome.shell.extensions.dash-to-dock icon-size-fixed true
gsettings set org.gnome.shell.extensions.dash-to-dock show-apps-at-top true
gsettings set org.gnome.shell.extensions.dash-to-dock animate-show-apps true
gsettings set org.gnome.shell.extensions.dash-to-dock custom-theme-shrink true
gsettings set org.gnome.shell.extensions.dash-to-dock apply-custom-theme false
gsettings set org.gnome.shell.extensions.dash-to-dock show-windows-preview true
gsettings set org.gnome.shell.extensions.dash-to-dock force-straight-corner true

gsettings set org.gnome.shell.extensions.dash-to-dock height-fraction 0.8
gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 24
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.26

gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
gsettings set org.gnome.shell.extensions.dash-to-dock scroll-action 'cycle-windows'
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'focus-or-previews'
gsettings set org.gnome.shell.extensions.dash-to-dock running-indicator-style 'SQUARES'

dconf write /org/gnome/shell/disabled-extensions = ['nightthemeswitcher@romainvigier.fr', 'desktop-icons@csoriano', 'openweather-extension@jenslody.de', 'gsconnect@andyholmes.github.io', 'drive-menu@gnome-shell-extensions.gcampax.github.com', 'launch-new-instance@gnome-shell-extensions.gcampax.github.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'dynamic-panel-transparency@rockon999.github.io', 'compiz-windows-effect@hermes83.github.com', 'panel-osd@berend.de.schouwer.gmail.com', 'gamemode@christian.kellner.me', 'appindicatorsupport@rgcjonas.gmail.com', 'native-window-placement@gnome-shell-extensions.gcampax.github.com', 'clipboard-indicator@tudmotu.com', 'ding@rastersoft.com', 'arch-update@RaphaelRochet', 'rss-feed@gnome-shell-extension.todevelopers.github.com', 'compiz-alike-windows-effect@hermes83.github.com', 'dash-to-dock@micxgx.gmail.com', 'auto-move-windows@gnome-shell-extensions.gcampax.github.com']



sed -i "s/#Server/Server/g" /etc/pacman.d/mirrorlist
