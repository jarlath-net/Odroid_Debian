#!/bin/bash

# ODROID_DEBIAN.sh



#-----------------------------------------------
# CONFIG
#-----------------------------------------------

#microSD or eMMC target device
export SDCARD=/dev/sdX

#Working dir (temporary files)
export WORKDIR=/home/user/ODROID/
#Mount point
export TARGET=/mnt/target/
#MAC address for ODROID
export MACADDR=72:e9:11:22:33:44
#Hostname
export TARGETNAME=ODROID
export ARCH=armhf
export DISTRIB=wheezy
#ROOT password for ODROID
export ROOTPASS=rootpass



#-----------------------------------------------
# CONFIG END
#-----------------------------------------------







#Create partitions on card
function CreatePartitions()
{

    sudo clear
    echo "	[*] Clear install: Preparing $SDCARD ..."
    echo "wipe card first sectors ..."
    sudo dd if=/dev/zero of=$SDCARD bs=4M count=1
    sync
    rm -Rf boot boot.tar.gz
    echo "Fuse card ..."
    wget http://odroid.in/guides/ubuntu-lfs/boot.tar.gz
    tar zxvf boot.tar.gz
    cd boot
    chmod +x sd_fusing.sh
    sudo ./sd_fusing.sh $SDCARD
    cd $WORKDIR

    echo "
    n
    p
    1
    3072
    +64M
    n
    p
    2
    134144

    t
    1
    c
    p
    w" | sudo fdisk $SDCARD



    sudo partprobe

    sudo mkfs.vfat -n BOOT $SDCARD"1"
    sudo mkfs.ext4 -L ROOTFS $SDCARD"2"
    sudo tune2fs -o journal_data_writeback $SDCARD"2"
    sudo tune2fs -O ^has_journal $SDCARD"2"
    sudo e2fsck -f $SDCARD"2"
    sudo dosfslabel $SDCARD"1" BOOT
    sudo e2label $SDCARD"2" ROOTFS
    sudo dumpe2fs $SDCARD"2" | head

}


function BootstrapDebian()
{
    sudo mkdir -p -v $TARGET
    sudo mount -v -t ext4 $SDCARD"2" $TARGET
    sudo qemu-debootstrap --foreign --arch=$ARCH $DISTRIB $TARGET http://http.debian.net/debian
    sudo sh -c "echo 'T0:23:respawn:/sbin/getty -L ttySAC1 115200 vt100'>> $TARGET'etc/inittab'"
    sudo sh -c "echo 'ttySAC1'>> $TARGET'etc/securetty'"


    cat <<__EOF__ | sudo tee $TARGET'etc/apt/sources.list'
# deb http://ftp.pl.debian.org/debian/ wheezy main

deb http://ftp.pl.debian.org/debian/ wheezy main contrib non-free
deb-src http://ftp.pl.debian.org/debian/ wheezy main contrib non-free

deb http://security.debian.org/ wheezy/updates main contrib non-free
deb-src http://security.debian.org/ wheezy/updates main contrib non-free

# wheezy-updates, previously known as 'volatile'
deb http://ftp.pl.debian.org/debian/ wheezy-updates main contrib non-free
deb-src http://ftp.pl.debian.org/debian/ wheezy-updates main contrib non-free
__EOF__


cat <<__EOF__ | sudo tee $TARGET'etc/apt/sources.list.d/backports.list'
deb http://ftp.pl.debian.org/debian wheezy-backports main contrib non-free
deb-src http://ftp.pl.debian.org/debian wheezy-backports main contrib non-free
__EOF__

sudo sh -c "echo $TARGETNAME> $TARGET'etc/hostname'"

cat <<__EOF__ | sudo tee $TARGET'etc/network/interfaces'
# The loopback network interface
auto lo
iface lo inet loopback
iface lo inet6 loopback

# eth0 network interface
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
__EOF__

cat <<__EOF__ | sudo tee $TARGET'etc/sysctl.d/local.conf'
# automatic reboot on kernel panic (5 secs)
panic = 5

# disable IPv6
##net.ipv6.conf.all.disable_ipv6 = 1
##net.ipv6.conf.default.disable_ipv6 = 1
##net.ipv6.conf.lo.disable_ipv6 = 1
__EOF__

cat <<__EOF__ | sudo tee $TARGET'etc/fstab'
LABEL=ROOTFS / ext4  errors=remount-ro,defaults,noatime,nodiratime 0 1
LABEL=BOOT /boot vfat defaults,rw,owner,flush,umask=000 0 0
tmpfs /tmp tmpfs nodev,nosuid,mode=1777 0 0

__EOF__

    sudo sh -c "echo $MACADDR> $TARGET'etc/smsc95xx_mac_addr'"

    sudo sh -c "echo 'exit 101'> $TARGET'usr/sbin/policy-rc.d'"
    sudo chmod -v +X $TARGET'usr/sbin/policy-rc.d'
    # Set root password
    sudo chroot $TARGET sh -c "echo $ROOTPASS'\n'$ROOTPASS | passwd root"

    sudo wget -O $TARGET'usr/local/bin/odroid-utility.sh' https://raw.githubusercontent.com/mdrjr/odroid-utility/master/odroid-utility.sh
    sudo chmod +x $TARGET'usr/local/bin/odroid-utility.sh'

    sudo mount -v -o bind /dev $TARGET'dev'
    sudo mount -v -o bind /dev/pts $TARGET'dev/pts'
    sudo mount -v -o bind /sys $TARGET'sys'
    sudo mount -v -t proc proc $TARGET'proc'

    DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET apt-get update

    DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET apt-get install -y lsb-release initramfs-tools tzdata locales uboot-mkimage ntp sudo openssh-server curl bash-completion

    sudo cp $TARGET'etc/initram-fs/initramfs.conf.dpkg-new' $TARGET'etc/initram-fs/initramfs.conf'
    sudo cp $TARGET'etc/initram-fs/update-initramfs.conf.dpkg-new' $TARGET'etc/initram-fs/update-initramfs.conf'

}


function PutKernelAndFirmware_U3()
{
    echo "	[*] Install kernel and modules ..."
    sudo mount -v -t vfat $SDCARD"1" $TARGET'boot'
cat <<__EOF__ | sudo tee $TARGET'boot/boot.script'
setenv initrd_high "0xffffffff"
setenv fdt_high "0xffffffff"
setenv bootcmd "fatload mmc 0:1 0x40008000 zImage; fatload mmc 0:1 0x42000000 uInitrd; bootm 0x40008000 0x42000000"
setenv bootargs "console=tty1 console=ttySAC1,115200n8 root=LABEL=ROOTFS panic=5 rootwait ro mem=2047M smsc95xx.turbo_mode=N"
boot
__EOF__

    sudo mkimage -A ARM -T script -n "boot.scr for ROOTFS" -d $TARGET'boot/boot.script' $TARGET'boot/boot.scr'
    sudo wget http://builder.mdrjr.net/kernel-3.8/00-LATEST/odroidu2.tar.xz -O $TARGET'root/odroidu2.tar.xz'
    sudo wget http://builder.mdrjr.net/tools/firmware.tar.xz -O $TARGET'root/firmware.tar.xz'

    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET xz -d /root/odroidu2.tar.xz
    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET tar xfv /root/odroidu2.tar > /dev/null

    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET xz -d /root/firmware.tar.xz
    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET tar xfv /root/firmware.tar -C /lib/firmware/ > /dev/null



    export K_VERSION=`ls $TARGET'lib/modules/'`
    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET update-initramfs -c -k $K_VERSION
    sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n "uInitrd $K_VERSION" -d $TARGET"boot/initrd.img-$K_VERSION" $TARGET'boot/uInitrd'


}


function Finish()
{


    sudo sh -c "cat $TARGET'etc/initramfs-tools/initramfs.conf' | sed s/'MODULES=most'/'MODULES=dep'/g> /tmp/a.conf"
    sudo mv /tmp/a.conf $TARGET'etc/initramfs-tools/initramfs.conf'

    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET service ntp stop
    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET service ssh stop

    sudo sh -c "cat $TARGET'etc/inittab' | sed s/'id:2:initdefault:'/'id:3:initdefault:'/g> /tmp/b.conf"
    sudo mv /tmp/b.conf $TARGET'etc/inittab'

    sudo sh -c "cat $TARGET'etc/inittab' | sed s/'id:1:initdefault:'/'id:3:initdefault:'/g> /tmp/b.conf"
    sudo mv /tmp/b.conf $TARGET'etc/inittab'

    sudo sh -c "echo 'FSCKFIX=yes'>> $TARGET'etc/default/rcS'"

    sudo umount -v $TARGET'dev/pts'
    sudo umount -v $TARGET'dev'
    sudo umount -v $TARGET'sys'
    sudo umount -v $TARGET'proc'

    sudo umount -v $TARGET'boot'

    sudo rm $TARGET'usr/sbin/policy-rc.d'

    sudo umount -v $TARGET
    sync
    sudo eject $SDCARD

    echo "----------------"
    echo "-= CARD READY =-"
    echo "----------------"


}

# Clear install: erase card and install from scratch
function ClearInstall()
{
    mkdir -v -p $WORKDIR
    cd $WORKDIR
    CreatePartitions
    BootstrapDebian
    PutKernelAndFirmware_U3
    Finish
}




sudo apt-get install qemu-user-static debootstrap u-boot-tools dosfstools parted

echo "ODROID U3 Debian build script"
echo "Script are given as-is without warrantly"
echo "All data on $SDCARD will be erased when go next step"
while true; do
    read -p "Do you wish to install Debian for Odroid-U3 on $SDCARD [y/n]  " yn
    case $yn in
        [Yy]* ) ClearInstall; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
