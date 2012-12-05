#!/bin/bash
#
# Author: Linaro Android Team <linaro-dev@lists.linaro.org>
#
# These files are Copyright (C) 2012 Linaro Limited and they
# are licensed under the Apache License, Version 2.0.
# You may obtain a copy of this license at
# http://www.apache.org/licenses/LICENSE-2.0


function show_usage() {
    echo "Usage:"
    echo -e "\t`basename $0` [--serial|-s serial] [--partition|-p boot-partition] boot.tar.bz2-file"
    echo -e "\t\tUpdate the kernel files in the boot partition of the specified"
    echo -e "\t\tandroid device with the specified boot.tar.bz2 file"
    echo ""
    echo -e "\t`basename $0` [--serial|-s serial] kernel-source-directory"
    echo -e "\t\tPush all the module files in the specified kernel dirctory"
    echo -e "\t\tinto the /system/modules dirctory of the specified android device"
    echo ""
    echo -e "\t`basename $0` --help|-h"
    echo -e "\t\tPrint out this help information"
}

function parse_argv() {
    while test -n "$1"; do
        case "$1" in
            --help|-h)
                show_usage
                exit 0
                ;;
            --serial|-s)
                serial=$2;
                shift 2
                ;;
            --partition|-p)
                boot_partition=$2;
                shift 2
                ;;
            *)
                if [ -n "${file_path}" ]; then
                    show_usage
                    echo "Too many arguments, see --help for details"
                    exit 1
                else
                    file_path="$1"
                    shift
                fi
                ;;
        esac
    done
}

function check_parameters(){
    if [ -n "${serial}" ]; then
        export ANDROID_SERIAL=${serial}
    else
        serial=`adb get-serialno|sed 's/\r//g'`
        if [ "X${serial}" == "Xunknown" ]; then
            echo "Can not get the serial number autotically,"
            echo "Please specify the serial number with the -s option"
            exit 1
        else
            export ANDROID_SERIAL=${serial}
        fi
    fi

    if [ -z "${file_path}" ]; then
        echo "Please specify the path of the boot.tar.bz2 file or the directory"
        echo "where all module files are stored"
        exit 1
    fi

    if [ ! -e "${file_path}" ]; then
        echo "The specified path(${file_path}) does not exist"
        exit 1
    fi
    if [ ! -f "${file_path}" ] && [ ! -d "${file_path}" ]; then
        echo "The specified path(${file_path}) is neither a file and nor a directory"
        exit 1
    fi
}

function check_device_status(){
    status=`adb get-state|sed 's/\r//g'`
    if [ "X${status}" != "Xdevice" ]; then
        echo "The device is not on line,"
        echo "Please check the device status"
        exit 1
    fi
}

function get_boot_partition(){
    product_device=`adb shell getprop ro.product.device|sed 's/\r//g'`
    case "X${product_device}" in
        "X" )
            echo "Failed to get the value of ro.build.product property"
            exit 1
            ;;
        "Xpandaboard" )
            boot_partition="mmcblk0p1"
            ;;
        "Xorigen" )
            boot_partition="mmcblk0p2"
            ;;
        "Xvexpress_a9" )
            boot_partition="mmcblk0p1"
            ;;
        "Xvexpress" )
            boot_partition="mmcblk0p1"
            ;;
        * )
            echo "The product device(${product_device}) is not supported!"
            exit 1
            ;;
    esac
}

function verify_kernel(){
    src_dir="${1}"
    tgt_dir="${2}"

    for f in `ls ${src_dir}`; do
        verify_file "${src_dir}/${f}" "${tgt_dir}"
        if [ $? -ne 0 ]; then
            return 1
        fi
    done
    return 0
}

function verify_file(){
   src_file="${0}"
   tgt_dir="${1}"
   src_name=`basename ${src_file}`
   src_md5sum=`md5sum ${src_file}|cut -d \  -f 1`
   tgt_md5sum=`adb shell md5sum ${tgt_dir}/${src_name}|cut -d \  -f 1`
   if [ "X${md5sum_src}" != "X${md5sum_tgt}" ];then
       echo "File ${src_file} is not the same in the device with the source"
       return 1
   fi
   return 0
}

function set_func_value(){
    if [ -f ${file_path} ]; then
        func_value='kernel'
    elif [ -d ${file_path} ]; then
        func_value='modules'
    fi
}

function update_modules(){
    tgt_dir='/system/modules/'

    modules_org=`mktemp -u -d /tmp/modules.XXX`
    echo "Pull the original module files for backup in ${modules_org}"
    adb pull ${tgt_dir} ${modules_org} &>/dev/null

    all_modules=`find ${file_path}/ -type f -name '*.ko'`
    OLD_LFS="${LFS}"
    IFS=$'\n'
    for f_module in ${all_modules}; do
        echo "Pushing file: ${f_module}"
        adb push "${f_module}" "${tgt_dir}" &>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to push file: ${f_module}"
            exit 1
        fi
        verify_file "${f_module}" "${tgt_dir}"
        if [ $? -ne 0 ]; then
            echo "Please to use the files in ${modules_org} to revovery manually"
            exit 1
        fi
    done
    LFS=${OLD_LFS}
    rm -fr "${modules_org}"
    echo "Updated module files successfully"
}

function update_kernel(){
    kernel_dir=`mktemp -d /tmp/boot.XXX`
    tar jxf ${file_path} -C ${kernel_dir}
    if [ $? -ne 0 ]; then
        echo "Failed to uncompress the boot file: ${file_path}"
        exit 1
    fi

    if [ -z "${boot_partition}" ]; then
        get_boot_partition
    fi
    adb shell mount -t vfat /dev/block/${boot_partition} ${mountpoint}
    kernel_org=`mktemp -u -d /tmp/boot.XXX`
    echo "Pull the original kernel files for backup in ${kernel_org}"
    adb pull ${mountpoint} ${kernel_org} &>/dev/null

    echo "Push the new kernel files to boot partition ${boot_partition}"
    adb push ${kernel_dir}/boot ${mountpoint} &>/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to push the kernel files"
        rm -fr ${kernel_dir}
        exit 1
    fi
    adb shell sync

    verify_kernel ${kernel_dir}/boot ${mountpoint}
    if [ $? -ne 0 ]; then
        echo "Failed the update the kernel files."
        echo "Please use the original files in ${kernel_org} to recovery manually"
        rm -fr ${kernel_dir}
        exit 1
    fi
    adb shell umount ${mountpoint}
    rm -fr ${kernel_dir} ${kernel_org}
    echo "Kernel updated successfully"
}

function main(){
    file_path=""
    serial=''
    mountpoint="/data/local/tmp"
    func_value=''

    parse_argv "$@"
    check_parameters
    check_device_status
    set_func_value
    update_${func_value}
}
main "$@"
