#!/bin/sh

set -u

OPTIND=1

VGPU=""
ROM=""
DEFAULT_DISK=""
DEFAULT_MEMORY=8192

usage() {
      cat 1>&2 <<EOF
qemu.sh v0
Wrapper for Qemu-kvm

USAGE:
    qemu.sh [FLAGS] [OPTIONS]

FLAGS:
    -h              Prints help information

OPTIONS:
    -i <name>               Boot ISO
    -d <name>               Hard Disk
    -m <mb>                 RAM
EOF
}

main() {
    local iso=""
    local disk=""
    local memory=""

    while getopts "h?i:d:m:" opt; do
        case "$opt" in
            h|\?)
                usage
                exit 0
                ;;
            i)
                iso=$OPTARG
                ;;
            d)
                disk=$OPTARG
                ;;
            m)
                memory=$OPTARG
                ;;
            *)
                ;;
        esac
    done

    [[ -z "$disk" ]] && disk=$DEFAULT_DISK
    [[ -z "$disk" ]] && { echo "Error: no disk set"; exit 1; }
    [[ -z "$memory" ]] && memory=$DEFAULT_MEMORY

    run "$iso" "$disk" "$memory"
}

run() {
  local iso=$1
  local disk=$2
  local memory=$3

  set -- "$@" -enable-kvm;
  set -- "$@" -m "$memory"; shift;
  set -- "$@" -machine type=pc,accel=kvm,kernel_irqchip=on;
  set -- "$@" -smp cores=2,threads=2,sockets=1,maxcpus=4;
  set -- "$@" -global PIIX4_PM.disable_s3=1;
  set -- "$@" -global PIIX4_PM.disable_s4=1;
  set -- "$@" -display gtk,gl=on;
  set -- "$@" -device vfio-pci,sysfsdev=/sys/devices/pci0000:00/0000:00:02.0/$VGPU,x-igd-opregion=on,ramfb=on,driver=vfio-pci-nohotplug,display=on;
  set -- "$@" -net nic,model=e1000;
  set -- "$@" -net user;
  set -- "$@" -vga none;
  [[ -z $iso ]] || set -- "$@" -boot d;
  [[ -z $iso ]] || set -- "$@" -cdrom "$iso"; shift;
  set -- "$@" -hda "$disk"; shift;

  echo "$@"
  #qemu-system-x86_64 "$@"
}

main "$@" || exit 1
