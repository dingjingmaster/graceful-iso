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
isofs_dir=""

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

# 显示配置
_show_config()
{
    local build_date
    build_date="$(date --utc --iso-8601=seconds -d "@${SOURCE_DATE_EPOCH}")"
    _msg_info "${app_name} 配置值如下："
    _msg_info "             架构:       ${arch}"
    _msg_info "         工作目录:       ${work_dir}"
    _msg_info "         安装目录:       ${install_dir}"
    _msg_info "         构建时间:       ${build_date}"
    _msg_info "       输出文件夹:       ${out_dir}"
    _msg_info "         GPG 指纹:       ${gpg_key:-None}"
    _msg_info "         配置文件:       ${profile}"
    _msg_info "  pacman 配置文件:       ${pacman_conf}"
    _msg_info "       镜像文件名:       ${img_name}"
    _msg_info "       ISO 卷标签:       ${iso_label}"
    _msg_info "       ISO 出版者:       ${iso_publisher}"
    _msg_info "         ISO 名字:       ${iso_application}"
    _msg_info "         引导模式:       ${bootmodes[*]}"
    _msg_info "       要安裝的包:       ${pkg_list[*]}"
}

_pacman()
{
    _msg_info "正在安裝軟件包到 '${airootfs_dir}/' ..."
    if [[ "${quiet}" = "y" ]]; then
        pacstrap -C "${work_dir}/pacman.conf" -c -G -M -- "${airootfs_dir}" "$@" &> /dev/null
    else
        pacstrap -C "${work_dir}/pacman.conf" -c -G -M -- "${airootfs_dir}" "$@"
    fi

    _msg_info "所有軟件包安裝完成!!!"
}

# 清除 airootfs
_cleanup()
{
    _msg_info "开始清除 airootfs ..."

    # 删除 /boot 下的文件
    if [[ -d "${airootfs_dir}/boot" ]]; then
        find "${airootfs_dir}/boot" -mindepth 1 -delete
    fi

    # 删除 pacman 数据库缓冲下的包文件 (*.tar.gz)
    if [[ -d "${airootfs_dir}/var/lib/pacman" ]]; then
        find "${airootfs_dir}/var/lib/pacman" -maxdepth 1 -type f -delete
    fi

    # 删除 pacman 数据库缓冲
    if [[ -d "${airootfs_dir}/var/lib/pacman/sync" ]]; then
        find "${airootfs_dir}/var/lib/pacman/sync" -delete
    fi

    # 删除 pacman 包缓冲
    if [[ -d "${airootfs_dir}/var/cache/pacman/pkg" ]]; then
        find "${airootfs_dir}/var/cache/pacman/pkg" -type f -delete
    fi

    # 删除所有的日志文件
    if [[ -d "${airootfs_dir}/var/log" ]]; then
        find "${airootfs_dir}/var/log" -type f -delete
    fi

    # 删除临时文件
    if [[ -d "${airootfs_dir}/var/tmp" ]]; then
        find "${airootfs_dir}/var/tmp" -mindepth 1 -delete
    fi

    # 删除 pacman 相关的文件
    find "${work_dir}" \( -name '*.pacnew' -o -name '*.pacsave' -o -name '*.pacorig' \) -delete

    # 创建一个空的 /etc/matchine-id
    printf '' > "${airootfs_dir}/etc/machine-id"

    _msg_info "完成!!!"
}

# 创建镜像
_mkairootfs_create_image()
{
    if (( $# < 1 )); then
        _msg_error "函数 '${FUNCNAME[0]}' 至少需要一个参数" 1
    fi

    image_path="${isofs_dir}/${install_dir}/${arch}/airootfs.sfs"
    if [[ "${airootfs_image_type}" =~ .*squashfs ]] ; then
        if [[ "${quiet}" == "y" ]]; then
            mksquashfs "$@" "${image_path}" -noappend "${airootfs_image_tool_options[@]}" -no-progress > /dev/null
        else
            mksquashfs "$@" "${image_path}" -noappend "${airootfs_image_tool_options[@]}"
        fi
    else
        _msg_error "不支持的镜像类型: '${airootfs_image_type}'" 1
    fi
}

# 从源目录在SquashFS中创建ext4文件系统
_mkairootfs_img()
{
    if [[ ! -e "${airootfs_dir}" ]]; then
        _msg_error "此路径 '${airootfs_dir}' 不存在" 1
    fi

    _msg_info "开始创建一个 32GB 的 ext4 镜像 ..."
    if [[ "${quiet}" == "y" ]]; then
        mkfs.ext4 -q -O '^has_journal,^resize_inode' -E 'lazy_itable_init=0' -m 0 -F -- "${airootfs_dir}.img" 32G
    else
        mkfs.ext4 -O '^has_journal,^resize_inode' -E 'lazy_itable_init=0' -m 0 -F -- "${airootfs_dir}.img" 32G
    fi

    tune2fs -c 0 -i 0 -- "${airootfs_dir}.img" > /dev/null
    _msg_info "完成!!!"

    _mount_airootfs
    _msg_info "正在复制 '${airootfs_dir}/' 到 '${work_dir}/mnt/airootfs/'..."
    cp -aT -- "${airootfs_dir}/" "${work_dir}/mnt/airootfs/"
    chown -- 0:0 "${work_dir}/mnt/airootfs/"
    _msg_info "完成!!!"
    _umount_airootfs

    install -d -m 0755 -- "${isofs_dir}/${install_dir}/${arch}"
    _msg_info "正在创建 SquashFS 镜像, 可能需要花点时间 ..."
    _mkairootfs_create_image "${airootfs_dir}.img"
    _msg_info "完成!!!"

    rm -- "${airootfs_dir}.img"
}

_mkairootfs_sfs()
{
    if [[ ! -e "${airootfs_dir}" ]]; then
        _msg_error "此路径 '${airootfs_dir}' 不存在" 1
    fi

    install -d -m 0755 -- "${isofs_dir}/${install_dir}/${arch}"
    _msg_info "正在创建 SquashFS 镜像, 这可能需要花点时间 ..."
    _mkairootfs_create_image "${airootfs_dir}"
    _msg_info "完成!!!"
}

_mkchecksum()
{
    _msg_info "创建 sha512sum ..."
    cd -- "${isofs_dir}/${install_dir}/${arch}"
    sha512sum airootfs.sfs > airootfs.sha512
    cd -- "${OLDPWD}"
    _msg_info "完成!!!"
}

_mksignature()
{
    _msg_info "开始给 SquashFS 镜像签名 ..."
    cd -- "${isofs_dir}/${install_dir}/${arch}"
    gpg --detach-sign --default-key "${gpg_key}" airootfs.sfs
    cd -- "${OLDPWD}"
    _msg_info "完成!!!"
}

# 单例运行
_run_once()
{
    if [[ ! -e "${work_dir}/build.${1}" ]]; then
        "$1"
        touch "${work_dir}/build.${1}"
    fi
}

# 使用自定义的cache 和 pacman hook 文件夹设置自定义的 pacman.conf
_make_pacman_conf()
{
    local _cache_dirs _system_cache_dirs _profile_cache_dirs
    _system_cache_dirs="$(pacman-conf CacheDir| tr '\n' ' ')"
    _profile_cache_dirs="$(pacman-conf --config "${pacman_conf}" CacheDir| tr '\n' ' ')"
   
   # only use the profile's CacheDir, if it is not the default and not the same as the system cache dir
   if [[ "${_profile_cache_dirs}" != "/var/cache/pacman/pkg" ]] && \
       [[ "${_system_cache_dirs}" != "${_profile_cache_dirs}" ]]; then
       _cache_dirs="${_profile_cache_dirs}"
   else
       _cache_dirs="${_system_cache_dirs}"
   fi
   
   _msg_info "复制自定义的 pacman.conf 到工作目录..."
   pacman-conf --config "${pacman_conf}" | \
       sed '/CacheDir/d;/DBPath/d;/HookDir/d;/LogFile/d;/RootDir/d' > "${work_dir}/pacman.conf"
   
   _msg_info "正在使用 pacman 缓冲文件夹: ${_cache_dirs}"

   sed "/\[options\]/a CacheDir = ${_cache_dirs}
        /\[options\]/a HookDir = ${airootfs_dir}/etc/pacman.d/hooks/" \
            -i "${work_dir}/pacman.conf"
}

# 准备工作目录并复制自定义的 airootfs 文件
_make_custom_airootfs()
{
    local passwd=()

    install -d -m 0755 -o 0 -g 0 -- "${airootfs_dir}"

    if [[ -d "${profile}/airootfs" ]]; then
        _msg_info "开始复制自定义的文件和设置到用户家目录..."
        cp -af --no-preserve=ownership -- "${profile}/airootfs/." "${airootfs_dir}"

        [[ -e "${airootfs_dir}/etc/shadow" ]] && chmod -f 0400 -- "${airootfs_dir}/etc/shadow"
        [[ -e "${airootfs_dir}/etc/gshadow" ]] && chmod -f 0400 -- "${airootfs_dir}/etc/gshadow"

        if [[ -e "${airootfs_dir}/etc/passwd" ]]; then
            while IFS=':' read -a passwd -r; do
                [[ "${passwd[5]}" == '/' ]] && continue
                [[ -z "${passwd[5]}" ]] && continue

                if [[ -d "${airootfs_dir}${passwd[5]}" ]]; then
                    chown -hR -- "${passwd[2]}:${passwd[3]}" "${airootfs_dir}${passwd[5]}"
                    chmod -f 0750 -- "${airootfs_dir}${passwd[5]}"
                else
                    install -d -m 0750 -o "${passwd[2]}" -g "${passwd[3]}" -- "${airootfs_dir}${passwd[5]}"
                fi
            done < "${airootfs_dir}/etc/passwd"
        fi
        _msg_info "完成!!!"
    fi
}

_make_packages()
{
    if [[ -n "${gpg_key}" ]]; then
        exec {ARCHISO_GNUPG_FD}<>"${work_dir}/pubkey.gpg"
        export ARCHISO_GNUPG_FD
    fi

    _pacman "${pkg_list[@]}"
    if [[ -n "${gpg_key}" ]]; then
        exec {ARCHISO_GNUPG_FD}<&-
        unset ARCHISO_GNUPG_FD
    fi
}

# Customize installation (airootfs)
_make_customize_airootfs()
{
    local passwd=()

    if [[ -e "${profile}/airootfs/etc/passwd" ]]; then
        _msg_info "正在复制 /etc/skel/* 到用户目录 ..."
        while IFS=':' read -a passwd -r; do
            (( passwd[2] >= 1000 && passwd[2] < 60000 )) || continue
            [[ "${passwd[5]}" == '/' ]] && continue
            [[ -z "${passwd[5]}" ]] && continue
            cp -dnRT --preserve=mode,timestamps,links -- "${airootfs_dir}/etc/skel" "${airootfs_dir}${passwd[5]}"
            chmod -f 0750 -- "${airootfs_dir}${passwd[5]}"
            chown -hR -- "${passwd[2]}:${passwd[3]}" "${airootfs_dir}${passwd[5]}"
   
        done < "${profile}/airootfs/etc/passwd"
        _msg_info "完成!!!"
    fi
   
    if [[ -e "${airootfs_dir}/root/customize_gracefullinux.sh" ]]; then
        _msg_info "正在运行 customize_gracefullinux.sh '${airootfs_dir}' chroot..."
        local run_cmd="/root/customize_gracefullinux.sh"
        _chroot_run
        rm -- "${airootfs_dir}/root/customize_gracefullinux.sh"
        _msg_info "完成!!! customize_gracefullinux.sh 运行完成."
    fi
}

 # Set up boot loaders
_make_bootmodes()
{
    local bootmode
    for bootmode in "${bootmodes[@]}"; do
        if typeset -f "_make_boot_${bootmode}" &> /dev/null; then
            _run_once "_make_boot_${bootmode}"
        else
            _msg_error "无效的 boot 模式: ${bootmode}" 1
        fi
    done
}

# Prepare kernel/initramfs ${install_dir}/boot/
_make_boot_on_iso()
{
    local ucode_image
    _msg_info "开始为 ISO-9660 文件系统准备内核和 initramfs ..."

    install -d -m 0755 -- "${isofs_dir}/${install_dir}/boot/${arch}"
    install -m 0644 -- "${airootfs_dir}/boot/initramfs-"*".img" "${isofs_dir}/${install_dir}/boot/${arch}/"
    install -m 0644 -- "${airootfs_dir}/boot/vmlinuz-"* "${isofs_dir}/${install_dir}/boot/${arch}/"

    for ucode_image in {intel-uc.img,intel-ucode.img,amd-uc.img,amd-ucode.img,early_ucode.cpio,microcode.cpio}; do
        if [[ -e "${airootfs_dir}/boot/${ucode_image}" ]]; then
            install -m 0644 -- "${airootfs_dir}/boot/${ucode_image}" "${isofs_dir}/${install_dir}/boot/"
            if [[ -e "${airootfs_dir}/usr/share/licenses/${ucode_image%.*}/" ]]; then
                install -d -m 0755 -- "${isofs_dir}/${install_dir}/boot/licenses/${ucode_image%.*}/"
                install -m 0644 -- "${airootfs_dir}/usr/share/licenses/${ucode_image%.*}/"* \
                    "${isofs_dir}/${install_dir}/boot/licenses/${ucode_image%.*}/"
            fi
        fi
    done

    _msg_info "完成!!!"
}

# Prepare /${install_dir}/boot/syslinux
_make_boot_bios.syslinux.mbr()
{
    _msg_info "开始设置从磁盘文件系统引导操作系统 ..."
    install -d -m 0755 -- "${isofs_dir}/${install_dir}/boot/syslinux"
    for _cfg in "${profile}/syslinux/"*.cfg; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
            s|%INSTALL_DIR%|${install_dir}|g;
            s|%ARCH%|${arch}|g" \
            "${_cfg}" > "${isofs_dir}/${install_dir}/boot/syslinux/${_cfg##*/}"
    done

    if [[ -e "${profile}/syslinux/splash.png" ]]; then
        install -m 0644 -- "${profile}/syslinux/splash.png" "${isofs_dir}/${install_dir}/boot/syslinux/"
    fi

    install -m 0644 -- "${airootfs_dir}/usr/lib/syslinux/bios/"*.c32 "${isofs_dir}/${install_dir}/boot/syslinux/"
    install -m 0644 -- "${airootfs_dir}/usr/lib/syslinux/bios/lpxelinux.0" "${isofs_dir}/${install_dir}/boot/syslinux/"
    install -m 0644 -- "${airootfs_dir}/usr/lib/syslinux/bios/memdisk" "${isofs_dir}/${install_dir}/boot/syslinux/"
   
    _run_once _make_boot_on_iso
   
    if [[ -e "${isofs_dir}/${install_dir}/boot/syslinux/hdt.c32" ]]; then
        install -d -m 0755 -- "${isofs_dir}/${install_dir}/boot/syslinux/hdt"
        if [[ -e "${airootfs_dir}/usr/share/hwdata/pci.ids" ]]; then
            gzip -c -9 "${airootfs_dir}/usr/share/hwdata/pci.ids" > \
                "${isofs_dir}/${install_dir}/boot/syslinux/hdt/pciids.gz"
        fi

        find "${airootfs_dir}/usr/lib/modules" -name 'modules.alias' -print -exec gzip -c -9 '{}' ';' -quit > \
                "${isofs_dir}/${install_dir}/boot/syslinux/hdt/modalias.gz"
    fi
   
   # Add other aditional/extra files to ${install_dir}/boot/
   if [[ -e "${airootfs_dir}/boot/memtest86+/memtest.bin" ]]; then
       # rename for PXE: https://wiki.archlinux.org/index.php/Syslinux#Using_memtest
       install -m 0644 -- "${airootfs_dir}/boot/memtest86+/memtest.bin" "${isofs_dir}/${install_dir}/boot/memtest"
       install -d -m 0755 -- "${isofs_dir}/${install_dir}/boot/licenses/memtest86+/"
       install -m 0644 -- "${airootfs_dir}/usr/share/licenses/common/GPL2/license.txt" \
                "${isofs_dir}/${install_dir}/boot/licenses/memtest86+/"
   fi

   _msg_info "完成!!! SYSLINUX 设置从磁盘文件系统引导完成."
}

# Prepare /isolinux
_make_boot_bios.syslinux.eltorito()
{
    _msg_info "开始设置系统从光盘引导 ..."
    install -d -m 0755 -- "${isofs_dir}/isolinux"
    for _cfg in "${profile}/isolinux/"*".cfg"; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
            s|%INSTALL_DIR%|${install_dir}|g;
            s|%ARCH%|${arch}|g" \
            "${_cfg}" > "${isofs_dir}/isolinux/${_cfg##*/}"
    done

    install -m 0644 -- "${airootfs_dir}/usr/lib/syslinux/bios/isolinux.bin" "${isofs_dir}/isolinux/"
    install -m 0644 -- "${airootfs_dir}/usr/lib/syslinux/bios/isohdpfx.bin" "${isofs_dir}/isolinux/"
    install -m 0644 -- "${airootfs_dir}/usr/lib/syslinux/bios/ldlinux.c32" "${isofs_dir}/isolinux/"

    # isolinux.cfg loads syslinux.cfg
    _run_once _make_boot_bios.syslinux.mbr
    _msg_info "完成!!! 成功设置系统从光盘引导."
}

# Prepare /EFI on ISO-9660
_make_efi()
{
    _msg_info "开始为ISO 9660文件系统准备 /EFI 目录 ..."

    install -d -m 0755 -- "${isofs_dir}/EFI/BOOT"
    install -m 0644 -- "${airootfs_dir}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" \
            "${isofs_dir}/EFI/BOOT/BOOTx64.EFI"

    install -d -m 0755 -- "${isofs_dir}/loader/entries"
    install -m 0644 -- "${profile}/efiboot/loader/loader.conf" "${isofs_dir}/loader/"

    for _conf in "${profile}/efiboot/loader/entries/"*".conf"; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
            s|%INSTALL_DIR%|${install_dir}|g;
            s|%ARCH%|${arch}|g" \
            "${_conf}" > "${isofs_dir}/loader/entries/${_conf##*/}"
    done

    # edk2-shell based UEFI shell
    # shellx64.efi is picked up automatically when on /
    if [[ -e "${airootfs_dir}/usr/share/edk2-shell/x64/Shell_Full.efi" ]]; then
        install -m 0644 -- "${airootfs_dir}/usr/share/edk2-shell/x64/Shell_Full.efi" "${isofs_dir}/shellx64.efi"
    fi
    _msg_info "完成!!!"
}

# Prepare kernel/initramfs on efiboot.img
_make_boot_on_fat()
{
    local ucode_image all_ucode_images=()
    _msg_info "为FAT文件系统准备内核和内部文件 ..."
    mmd -i "${work_dir}/efiboot.img" \
        "::/${install_dir}" "::/${install_dir}/boot" "::/${install_dir}/boot/${arch}"

    mcopy -i "${work_dir}/efiboot.img" "${airootfs_dir}/boot/vmlinuz-"* \
        "${airootfs_dir}/boot/initramfs-"*".img" "::/${install_dir}/boot/${arch}/"

    for ucode_image in \
        "${airootfs_dir}/boot/"{intel-uc.img,intel-ucode.img,amd-uc.img,amd-ucode.img,early_ucode.cpio,microcode.cpio}
    do
        if [[ -e "${ucode_image}" ]]; then
            all_ucode_images+=("${ucode_image}")
        fi
    done

    if (( ${#all_ucode_images[@]} )); then
        mcopy -i "${work_dir}/efiboot.img" "${all_ucode_images[@]}" "::/${install_dir}/boot/"
    fi

    _msg_info "完成!!!"
}

# Prepare efiboot.img::/EFI for EFI boot mode
_make_boot_uefi-x64.systemd-boot.esp()
{
    local efiboot_imgsize="0"
    _msg_info "开始设置系统引导方式为 UEFI ..."
   
    # the required image size in KiB (rounded up to the next full MiB with an additional MiB for reserved sectors)
    efiboot_imgsize="$(du -bc \
        "${airootfs_dir}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" \
        "${airootfs_dir}/usr/share/edk2-shell/x64/Shell_Full.efi" \
        "${profile}/efiboot/" \
        "${airootfs_dir}/boot/vmlinuz-"* \
        "${airootfs_dir}/boot/initramfs-"*".img" \
        "${airootfs_dir}/boot/"{intel-uc.img,intel-ucode.img,amd-uc.img,amd-ucode.img,early_ucode.cpio,microcode.cpio} \
        2>/dev/null | awk 'function ceil(x){return int(x)+(x>int(x))}
            function byte_to_kib(x){return x/1024}
            function mib_to_kib(x){return x*1024}
            END {print mib_to_kib(ceil((byte_to_kib($1)+1024)/1024))}'
        )"

    # The FAT image must be created with mkfs.fat not mformat, as some systems have issues with mformat made images:
    # https://lists.gnu.org/archive/html/grub-devel/2019-04/msg00099.html
    [[ -e "${work_dir}/efiboot.img" ]] && rm -f -- "${work_dir}/efiboot.img"
    _msg_info "Creating FAT image of size: ${efiboot_imgsize} KiB..."
    mkfs.fat -C -n ARCHISO_EFI "${work_dir}/efiboot.img" "$efiboot_imgsize"

    mmd -i "${work_dir}/efiboot.img" ::/EFI ::/EFI/BOOT
    mcopy -i "${work_dir}/efiboot.img" \
        "${airootfs_dir}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" ::/EFI/BOOT/BOOTx64.EFI

    mmd -i "${work_dir}/efiboot.img" ::/loader ::/loader/entries
    mcopy -i "${work_dir}/efiboot.img" "${profile}/efiboot/loader/loader.conf" ::/loader/
    for _conf in "${profile}/efiboot/loader/entries/"*".conf"; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
            s|%INSTALL_DIR%|${install_dir}|g;
            s|%ARCH%|${arch}|g" \
            "${_conf}" | mcopy -i "${work_dir}/efiboot.img" - "::/loader/entries/${_conf##*/}"
    done

    # shellx64.efi is picked up automatically when on /
    if [[ -e "${airootfs_dir}/usr/share/edk2-shell/x64/Shell_Full.efi" ]]; then
        mcopy -i "${work_dir}/efiboot.img" \
            "${airootfs_dir}/usr/share/edk2-shell/x64/Shell_Full.efi" ::/shellx64.efi
    fi

    # Copy kernel and initramfs
    _make_boot_on_fat

    _msg_info "完成!!!"
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
_make_boot_uefi-x64.systemd-boot.eltorito()
{
    _run_once _make_boot_uefi-x64.systemd-boot.esp
    # Set up /EFI on ISO-9660
    _run_once _make_efi
}

# Build airootfs filesystem image
_make_prepare()
{
    if [[ "${airootfs_image_type}" == "squashfs" ]]; then # prepare airootfs.sfs for overlayfs usage (default)
        _run_once _mkairootfs_sfs
    elif [[ "${airootfs_image_type}" == "ext4+squashfs" ]]; then # prepare airootfs.sfs for dm-snapshot usage
        _run_once _mkairootfs_img
    else
        _msg_error "Unsupported image type: '${airootfs_image_type}'" 1
    fi
    
    _mkchecksum
    
    if [[ "${gpg_key}" ]]; then
        _mksignature
    fi
}

# Build ISO
_make_iso()
{
    local xorrisofs_options=()

    [[ -d "${out_dir}" ]] || install -d -- "${out_dir}"

    if [[ "${quiet}" == "y" ]]; then
        xorrisofs_options+=('-quiet')
    fi
   
    # xorrisofs options for x86 BIOS booting using SYSLINUX
    # shellcheck disable=SC2076
    if [[ " ${bootmodes[*]} " =~ ' bios.syslinux.' ]]; then
        # SYSLINUX El Torito
        if [[ " ${bootmodes[*]} " =~ ' bios.syslinux.eltorito ' ]]; then
            if [[ ! -f "${isofs_dir}/isolinux/isolinux.bin" ]]; then
                _msg_error "The file '${isofs_dir}/isolinux/isolinux.bin' does not exist." 1
            fi
   
            # SYSLINUX MBR
            if [[ " ${bootmodes[*]} " =~ ' bios.syslinux.mbr ' ]]; then
                if [[ ! -f "${isofs_dir}/isolinux/isohdpfx.bin" ]]; then
                    _msg_error "The file '${isofs_dir}/isolinux/isohdpfx.bin' does not exist." 1
                fi

                xorrisofs_options+=(
                    # SYSLINUX MBR bootstrap code; does not work without "-eltorito-boot isolinux/isolinux.bin"
                    '-isohybrid-mbr' "${isofs_dir}/isolinux/isohdpfx.bin"
                    # When GPT is used, create an additional partition in the MBR (besides 0xEE) for sectors 0–1 (MBR
                    # bootstrap code area) and mark it as bootable
                    # This violates the UEFI specification, but may allow booting on some systems
                    # https://wiki.archlinux.org/index.php/Partitioning#Tricking_old_BIOS_into_booting_from_GPT
                    '--mbr-force-bootable'
                    # Set the ISO 9660 partition's type to "Linux filesystem data"
                    # When only MBR is present, the partition type ID will be 0x83 "Linux" as xorriso translates all
                    # GPT partition type GUIDs except for the ESP GUID to MBR type ID 0x83
                    '-iso_mbr_part_type' '0FC63DAF-8483-4772-8E79-3D69D8477DE4'
                    # Move the first partition away from the start of the ISO to match the expectations of partition
                    # editors
                    # May allow booting on some systems
                    # https://dev.lovelyhq.com/libburnia/libisoburn/src/branch/master/doc/partition_offset.wiki
                    '-partition_offset' '16'
                )
            fi
   
            xorrisofs_options+=(
                # El Torito boot image for x86 BIOS
                '-eltorito-boot' 'isolinux/isolinux.bin'
                # El Torito boot catalog file
                '-eltorito-catalog' 'isolinux/boot.cat'
                # Required options to boot with ISOLINUX
                '-no-emul-boot' '-boot-load-size' '4' '-boot-info-table'
            )
        else
            _msg_error "Using 'bios.syslinux.mbr' boot mode without 'bios.syslinux.eltorito' is not supported." 1
        fi
    fi

    # xorrisofs options for X64 UEFI booting using systemd-boot
    # shellcheck disable=SC2076
    if [[ " ${bootmodes[*]} " =~ ' uefi-x64.systemd-boot.' ]]; then
        if [[ ! -f "${work_dir}/efiboot.img" ]]; then
            _msg_error "The file '${work_dir}/efiboot.img' does not exist." 1
        fi

        [[ -e "${isofs_dir}/EFI/archiso" ]] && rm -rf -- "${isofs_dir}/EFI/archiso"
   
        # systemd-boot in an attached EFI system partition
        if [[ " ${bootmodes[*]} " =~ ' uefi-x64.systemd-boot.esp ' ]]; then
            # Move the first partition away from the start of the ISO, otherwise the GPT will not be valid and ISO 9660
            # partition will not be mountable
            [[ " ${xorrisofs_options[*]} " =~ ' -partition_offset ' ]] || xorrisofs_options+=('-partition_offset' '16')
            xorrisofs_options+=(
                # Attach efiboot.img as a second partition and set its partition type to "EFI system partition"
                '-append_partition' '2' 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B' "${work_dir}/efiboot.img"
                # Ensure GPT is used as some systems do not support UEFI booting without it
                '-appended_part_as_gpt'
            )

            # systemd-boot in an attached EFI system partition via El Torito
            if [[ " ${bootmodes[*]} " =~ ' uefi-x64.systemd-boot.eltorito ' ]]; then
                xorrisofs_options+=(
                    # Start a new El Torito boot entry for UEFI
                    '-eltorito-alt-boot'
                    # Set the second partition as the El Torito UEFI boot image
                    '-e' '--interval:appended_partition_2:all::'
                    # Boot image is not emulating floppy or hard disk; required for all known boot loaders
                    '-no-emul-boot'
                )
            fi

        # systemd-boot in an embedded efiboot.img via El Torito
        elif [[ " ${bootmodes[*]} " =~ ' uefi-x64.systemd-boot.eltorito ' ]]; then
            # The ISO will not contain a GPT partition table, so to be able to reference efiboot.img, place it as a
            # file inside the ISO 9660 file system
            install -d -m 0755 -- "${isofs_dir}/EFI/archiso"
            cp -a -- "${work_dir}/efiboot.img" "${isofs_dir}/EFI/archiso/efiboot.img"
   
            xorrisofs_options+=(
                # Start a new El Torito boot entry for UEFI
                '-eltorito-alt-boot'
                # Set efiboot.img as the El Torito UEFI boot image
                '-e' 'EFI/archiso/efiboot.img'
                # Boot image is not emulating floppy or hard disk; required for all known boot loaders
                '-no-emul-boot'
            )
        fi

        # Specify where to save the El Torito boot catalog file in case it is not already set by bios.syslinux.eltorito
        [[ " ${bootmodes[*]} " =~ ' bios.' ]] || xorrisofs_options+=('-eltorito-catalog' 'EFI/boot.cat')
    fi

    _msg_info "开始创建 ISO 镜像 ..."
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -joliet \
        -joliet-long \
        -rational-rock \
        -volid "${iso_label}" \
        -appid "${iso_application}" \
        -publisher "${iso_publisher}" \
        -preparer "prepared by ${app_name}" \
        "${xorrisofs_options[@]}" \
        -output "${out_dir}/${img_name}" \
        "${isofs_dir}/"

    _msg_info "完成!!!"
    du -h -- "${out_dir}/${img_name}"
}

# Read profile's values from profiledef.sh
_read_profile()
{
    if [[ -z "${profile}" ]]; then
        _msg_error "No profile specified!" 1
    fi

    if [[ ! -d "${profile}" ]]; then
        _msg_error "Profile '${profile}' does not exist!" 1
    elif [[ ! -e "${profile}/profiledef.sh" ]]; then
        _msg_error "Profile '${profile}' is missing 'profiledef.sh'!" 1
    else
        cd -- "${profile}"

        # Source profile's variables
        # shellcheck source=configs/releng/profiledef.sh
        . "${profile}/profiledef.sh"

        # Resolve paths
        packages="$(realpath -- "${profile}/packages.${arch}")"
        pacman_conf="$(realpath -- "${pacman_conf}")"

        # Enumerate packages
        [[ -e "${packages}" ]] || _msg_error "File '${packages}' does not exist!" 1
        mapfile -t pkg_list < <(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${packages}")

        cd -- "${OLDPWD}"
    fi
}

# set overrides from mkarchiso option parameters, if present
_set_overrides()
{
    if [[ -n "$override_iso_label" ]]; then
        iso_label="$override_iso_label"
    fi

    if [[ -n "$override_iso_publisher" ]]; then
        iso_publisher="$override_iso_publisher"
    fi

    if [[ -n "$override_iso_application" ]]; then
        iso_application="$override_iso_application"
    fi

    if [[ -n "$override_install_dir" ]]; then
        install_dir="$override_install_dir"
    fi

    if [[ -n "$override_pacman_conf" ]]; then
        pacman_conf="$override_pacman_conf"
    fi

    if [[ -n "$override_gpg_key" ]]; then
        gpg_key="$override_gpg_key"
    fi
}

_export_gpg_publickey()
{
    if [[ -n "${gpg_key}" ]]; then
        gpg --batch --output "${work_dir}/pubkey.gpg" --export "${gpg_key}"
    fi
}

_make_pkglist()
{
    install -d -m 0755 -- "${isofs_dir}/${install_dir}"
    _msg_info "在 live 环境下安装软件包 ..."
    pacman -Q --sysroot "${airootfs_dir}" > "${isofs_dir}/${install_dir}/pkglist.${arch}.txt"
    _msg_info "完成!!!"
}

_build_profile()
{
    # Set up essential directory paths
    airootfs_dir="${work_dir}/${arch}/airootfs"
    isofs_dir="${work_dir}/iso"
    
    # Set ISO file name
    img_name="${iso_name}-${iso_version}-${arch}.iso"

    # Create working directory
    [[ -d "${work_dir}" ]] || install -d -- "${work_dir}"
    
    # Write build date to file or if the file exists, read it from there
    if [[ -e "${work_dir}/build_date" ]]; then
        SOURCE_DATE_EPOCH="$(<"${work_dir}/build_date")"
    else
        printf '%s\n' "$SOURCE_DATE_EPOCH" > "${work_dir}/build_date"
    fi
    
    _show_config
    _run_once _make_pacman_conf
    _run_once _export_gpg_publickey
    _run_once _make_custom_airootfs
    _run_once _make_packages
    _run_once _make_customize_airootfs
    _run_once _make_pkglist
    _make_bootmodes
    _run_once _cleanup
    _run_once _make_prepare
    _run_once _make_iso
}

while getopts 'p:r:C:L:P:A:D:w:o:g:vh?' arg; do
    case "${arg}" in
        p)
            read -r -a opt_pkg_list <<< "${OPTARG}"
            pkg_list+=("${opt_pkg_list[@]}")
            ;;
        r) run_cmd="${OPTARG}" ;;
        C) override_pacman_conf="$(realpath -- "${OPTARG}")" ;;
        L) override_iso_label="${OPTARG}" ;;
        P) override_iso_publisher="${OPTARG}" ;;
        A) override_iso_application="${OPTARG}" ;;
        D) override_install_dir="${OPTARG}" ;;
        w) work_dir="$(realpath -- "${OPTARG}")" ;;
        o) out_dir="$(realpath -- "${OPTARG}")" ;;
        g) override_gpg_key="${OPTARG}" ;;
        v) quiet="n" ;;
        h|?) _usage 0 ;;
        *)
            _msg_error "无效的输入参数 '${arg}'" 0
            _usage 1
            ;;
    esac
done
   
shift $((OPTIND - 1))
   
if (( $# < 1 )); then
    _msg_error "未指定配置文件" 0
    _usage 1
fi
   
if (( EUID != 0 )); then
    _msg_error "${app_name} 必须以 root 运行." 1
fi
   
# get the absolute path representation of the first non-option argument
profile="$(realpath -- "${1}")"
airootfs_dir="${work_dir}/airootfs"
isofs_dir="${work_dir}/iso"
   
# Set directory path defaults for legacy commands
_read_profile
_set_overrides
_build_profile

