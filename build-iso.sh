#!/bin/bash

set -e -u

# 配置环境
umask 0022
export LANG="C"
export SOUCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-"$(date +%s)"}"

# 镜像相关
app_name="${0##*/}"
pkg_list=()
run_cmd=""
quiet="y"
work_dir="work"
out_dir="out"
img_name="${app_name}.iso"
gpg_key=""
override_gpg_key=""

# 默认配置
profile=""
iso_name="${app_name}"
iso_label="${app_name^^}"
override_iso_label=""
iso_publisher="${app_name}"
override_iso_publisher=""
iso_application="${app_name} iso"
override_iso_application=""
iso_version=""
install_dir="${app_name}"
override_install_dir=""
arch="$(uname -m)"
pacman_conf="/etc/pacman.conf"
override_pacman_conf=""
bootmodes=()
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz')

# 用到的全局变量
airootfs_dir=""

# 输出信息
_msg_info() 
{
    local _msg="${1}"
    [[ "${quiet}" == "y" ]] || printf '[%s] INFO: %s\n' "${app_name}" "${_msg}"
}

# 输出警告
_msg_warning()
{
    local _msg="${1}"
    printf '[%s] WARNING: %s\n' "${app_name}" "${_msg}" >&2
}

# 输出错误
_msg_error()
{
    local _msg="${1}"
    local _error="${2}"
    printf '[%s] ERROR: %s\n' "${app_name}" "${_msg}" >&2
    if (( _error > 0 )); then
        exit "${error}"
    fi
}

_chroot_init()
{
    install -d -m 0755 -o 0 -g 0 -- "${airootfs_dir}"
    _pacman base syslinux
}

_chroot_run()
{
    eval -- arch-chroot "${airootfs_dir}" "${run_cmd}"
}

_mount_airootfs()
{
    trap "_umount_airootfs" EXIT HUB INT TERM
    install -d -m 0755 -- "${work_dir}/mnt/airootfs"
    _msg_info "正在把 '${airootfs_dir}.img' 挂载到 '${work_dir}/mnt/airootfs' ..."
    mount -- "${airootfs_dir}.img" "${work_dir}/mnt/airootfs"
    _msg_info "成功!!!"
}

# 显示帮助信息
_usage()
{
    IFS='' read -r -d '' usagetext <<ENDUSAGETEXT || true
使用方法: ${app_name} [选项] <配置文件所在文件夹>
    选项:
        -A <程序名字>       给生成的镜像设置文件
                            默认: '${iso_application}'
        -C <文件>           pacman 的配置文件
                            默认: '${pacman_conf}'
        -D <安装文件夹>     设置安装文件夹，所有文件都以此为根路径
                            默认: '${install_dir}'
                            注意: 最多使用八字节，仅仅使用[a-z0-9]
        -L <标签>           设置 ISO 卷的标签
                            默认: '${iso_label}'
        -P <出版者>         设置 ISO 的出版者
                            默认: '${iso_publisher}'
        -g <gpg_key>        设置 GPG 用以给 sqashfs 镜像签名
        -h                  显示此帮助信息
        -o <输出文件夹>     设置镜像的输出文件夹
                            默认: '${out_dir}'
        -p 包名             要安装的包
        -v                  输出详细信息
        -w <工作目录>       设置工作目录
                            默认: '${work_dir}'

    配置文件夹:             包含 iso 鏡像構建配置的文件夾
ENDUSAGETEXT
    printf '%s' "${usagetext}"
    exit "${1}"
}
