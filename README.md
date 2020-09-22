# Introduction
Intel GVT-g is this cool feature supported by modern Intel iGPUs to split into small GPUs that can be assigned to virtual machines.

However this feature is not well supported and finding a setup that actually works can be quite time consuming. Especially when using this feature with Windows VMs it ends to break in quite imaginative ways. This is an attempt to document the setup I got it to work with.
 
**Limitations:** This setup assumes for 8th Generation (Coffee Lake) with UHD Grapchis 630 it may or may not work for other cpu. It assumes you use an arch based Linux distribution but it should also work for other Linux distributions.

# Setup
## Kernel Preparation

Make sure you use a supported kernel. The minimum version required for GVT-g `4.19.x`, at the time of writing this I couldn't get GVT-g to work with any Version newer than `5.4.x` any Version in between probably works.

Edit `/etc/mkinitcpio.conf` and the required modules to loaded early.
```
MODULES=(kvgt vfio vfio-iommu-type1 vfio-mdev)
```
Rebuild initramfs (`mkinitcpio -p linux` when using vanilla arch).

Add the required kernel command line parameters.
```
i915.enable_gvt=1 kvm.ignore_msrs=1
```
Many ressources recommend also adding `i915.enable_guc=0` to avoid crashes but I didn't find this to be necessary.

## vGPU setup

Find the pci device ID for the iGPU using `lspci`. It should look similar to this.
```
00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630 (Mobile)
```
You can than list the types of of supported vGPU by looking into `/sys/devices/pci0000:000/0000:$PCI_ID/mdev_supported_types/`. The number of folders may differ depending on the amount ram allocated to your iGPU you may need to increase this in your UEFI. There should be at least one configuration that supports resolutions up to `1920x1200`. You can see the resolution by looking into the description file.
```
[buengese@ws ~]$ cat /sys/devices/pci0000\:00/0000\:00\:02.0/mdev_supported_types/i915-GVTg_V5_4/description 
low_gm_size: 128MB
high_gm_size: 512MB
fence: 4
resolution: 1920x1200
weight: 4
```
You can create UUID for the vGPU using uuigen. We'll save it in an environment variable because we need it later. After that we can create the vGPU
```
VGPU_UUID=$(uuidgen)
sudo bash -c "echo $VGPU_UUID > /sys/devices/pci0000:00/0000:$PCI_ID/mdev_supported_types/$vGPU_TYPE/create"
```
You can also generate an vGPU automatically on startup by editing and using the systemd service included with this document.

## Udev rules

We'll add a udev rule so we can run qemu with the vGPU without root. Create `/etc/udev/rules.d/10-qemu.rules` with this content.
```
SUBSYSTEM=="vfio", OWNER="root", GROUP="kvm"
```

## Qemu setup

For the qemu setup the most important option is the machine type. We have the option between i440fx (BIOS) and q35 (UEFI). 

You should probably try both - It's very likely that one work significantly better than the other (or one may not work at all) depending on your hardware.

The basic setup for i440fx looks like this
```
#!/bin/sh
# Start QEMU
qemu-system-x86_64 \
    -enable-kvm \
    -m 8G \
    -smp cores=2,threads=2,sockets=1,maxcpus=4 \
    -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
    -machine type=pc,accel=kvm,kernel_irqchip=on \
    -global PIIX4_PM.disable_s3=1 \
    -global PIIX4_PM.disable_s4=1 \
    -name windows-gvt-g-guest \
    -display gtk,gl=on \
    -device vfio-pci,sysfsdev=/sys/devices/pci0000:00/0000:$PCI_ID/$VGPU_UUID,x-igd-opregion=on,ramfb=on,driver=vfio-pci-nohotplug,display=on \
    -drive file=/path/to/your/windows.qcow2,format=qcow2,l2-cache-size=8M \
    -cdrom /path/to/your/windows_installer.iso \
    -vga none \
    -net nic,model=e1000 \
    -net user
```
Note the `ramfb=on,driver-vfio-pci-nohotplug` part is only needed as long as the driver isn't installed and to see the boot process and can in theory be removed after the driver is installed and working. Alternatively you could also add a qxl display.

For q35 you also have to install `edk2-ovmf`. The basic setup looks like this.
```
#!/bin/sh
# Start QEMU
qemu-system-x86_64 \
    -enable-kvm \
    -m 8G \
    -smp cores=2,threads=2,sockets=1,maxcpus=4 \
    -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
    -machine q35,kernel_irqchip=on \
    -drive if=pflash,format=raw,readonly,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=/tmp/MY_VARS.fd \
    -name windows-gvt-g-guest \
    -display gtk,gl=on \
    -device vfio-pci,sysfsdev=/sys/devices/pci0000:00/0000:$PCI_ID/$VGPU_UUID,x-igd-opregion=on,romfile=/path/to/vbios_gvt_uefi.rom,ramfb=on,driver=vfio-pci-nohotplug,display=on \
    -drive file=/path/to/your/windows.qcow2,format=qcow2,l2-cache-size=8M \
    -cdrom /path/to/your/windows_installer.iso \
    -vga none \
    -net nic,model=e1000 \
    -net user
```
The `vbios_gvt_uefi.rom` is included in this repo. It's sourced from [this patch](https://bugzilla.tianocore.org/show_bug.cgi?id=935#c12) which can alternatively be applied to i915.

In this repo are also 2 allready prepared shell scripts.

## Installing Windows

The installation of Windows can be performt the usual way. It's advisable to disable networking for the VM while Windows is installing and [disable automatic driver installation/updates](https://windowsloop.com/disable-automatic-driver-installation-on-windows-10/) before enabling networking. 

The disabling of automatic driver updates is very important - at the time of writing this the latest Intel drivers are completely broken and will probably render the VM unbootable.

The last step is now to install the correct GPU driver. This is the most annoying step most driver versions are broken in one way or another and you may have to try multiple versions. I've tried to list the driver versions with the highest success chance here.

For 5th gen (Broadwell) use Legacy Version 15.40.37.4835, for 6th and 7th gen (Skylake & Kaby Lake) use Legacy Version 15.45.23.4860. 

For 8th gen (Coffee Lake) there are multiple Versions you can try.
- 25.20.100.6326 seems to work best for me with i440fx
- 25.20.100.6444 also seems to work for some people
- 25.20.100.6471 to 26.20.100.7000 don't seem to work with i440fx but may work with q35
- 27.xx.xxx.xxxx don't work at all