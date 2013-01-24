#!/bin/bash

# Author: Linaro Android Team <linaro-dev@lists.linaro.org>
#
# These files are Copyright (C) 2012 Linaro Limited and they
# are licensed under the Apache License, Version 2.0.
# You may obtain a copy of this license at
# http://www.apache.org/licenses/LICENSE-2.0


function show_usage() {
    echo "Usage:"
    echo -e "\t`basename $0` [--serial|-s <serial>] [--partition|-p <boot-partition>] [--target|-t <target-file>] <source-file>"
    echo -e "\t\tUpdate the target file in uInitrd of the specified device"
    echo -e "\t\twith the specified source file"
    echo -e "\t\tWhen the target file is not specified, will update the file in"
    echo -e "\t\tthe root directory that has the same file name of the source file"
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
            --target|-t)
                tgt_file=$2;
                shift 2
                ;;
            *)
                if [ -n "${src_file}" ]; then
                    show_usage
                    echo "Too many arguments, see --help for details"
                    exit 1
                else
                    src_file="$1"
                    shift
                fi
                ;;
        esac
    done
}

function export_serial(){
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
}


function check_parameters(){
    if [ -z "${src_file}" ]; then
        echo "Please specify the path of the source file want to use"
        exit 1
    fi

    if [ ! -f "${src_file}" ]; then
        echo "The specified path(${src_file}) is not a file"
        exit 1
    fi

#    will use the basename of the src_file
#    if [ -z "${tgt_file}" ]; then
#        echo "Please specify the path of the target file want to be updated"
#        exit 1
#    fi
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
    adb shell ls "/dev/block/${boot_partition}"|grep "/dev/block/${boot_partition}" >&/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to get the boot partition of your device."
        echo "Please specify the boot partition with the -p option."
        exit 1
    fi
}

function recreate_uinitrd(){
    uinitrd_f="$1"
    src_f="$2"
    tgt_f="$3"
    old_pwd=`pwd`

    src_dir=`dirname $src_f`
    src_name=`basename $src_f`
    cd $src_dir
    src_dir_abs_path=`pwd`
    src_file_abs="${src_dir_abs_path}/${src_name}"
    cd ${old_pwd}

    uinitrd_dir=`dirname $uinitrd_f`
    uinitrd_name=`basename $uinitrd_f`
    cd ${uinitrd_dir}

    dd if=${uinitrd_name} of=uInitrd.data ibs=64 skip=1
    mv uInitrd.data ramdisk.cpio.gz
    gzip -d -f ramdisk.cpio.gz
    cpio -i -F ramdisk.cpio
    cp -vf ${src_file_abs} ./${tgt_f}
    cpio -i -t -F ramdisk.cpio | cpio -o -H newc | gzip > ramdisk_new.cpio.gz
    mkimage -A arm -O linux -T ramdisk -n "Android Ramdisk Image" -d ramdisk_new.cpio.gz uInitrd

    cd ${old_pwd}
}

function update_uinitrd(){
    if [ -z "${boot_partition}" ]; then
        get_boot_partition
    fi
    adb shell mount -t vfat /dev/block/${boot_partition} ${mountpoint}
    adb shell mount|grep "/dev/block/${boot_partition}" >&/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to mount the boot partion /dev/block/${boot_partition}"
        exit 1
    fi

    org_uinitrd=`mktemp -d /tmp/uinitrd.XXX`
    echo "Pull the original uInitrd file for backup in ${org_uinitrd}"
    adb pull ${mountpoint}/uInitrd ${org_uinitrd} &>/dev/null
    cp -uvf $org_uinitrd/uInitrd{,.org}
    recreate_uinitrd "${org_uinitrd}/uInitrd" "${src_file}" "${tgt_file}"

    adb push ${org_uinitrd}/uInitrd ${mountpoint}/uInitrd
    adb push ${org_uinitrd}/uInitrd.org ${mountpoint}/uInitrd.org

    adb shell sync
    adb shell umount ${mountpoint}
    rm -fr ${org_uinitrd}
    echo "uInitrd updated successfully"
}

function main(){
    src_file=""
    tgt_file=""
    partition=""
    serial=""
    mountpoint="/data/local/tmp"

    parse_argv "$@"
    check_parameters
    if [ -z "$tgt_file" ]; then
        tgt_file=`basename ${src_file}`
    fi
    export_serial
    check_device_status
    update_uinitrd
}
main "$@"
