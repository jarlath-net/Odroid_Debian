#!/bin/bash
# ODROID_DEBIAN.sh


MACADDR=72:e9:11:22:33:44





TEMP_LOG="/tmp/odroid.build"
WORKDIR=/tmp/ODROID/
TARGET=/mnt/target/
ARCH=armhf
DISTRIB=wheezy

#Create partitions on card
function CreatePartitions()
{
    echo "      [*] Clear install: Preparing $SDCARD ..."
    echo "wipe card first sectors ..."
    sudo partprobe  >> $TEMP_LOG
    sudo dd if=/dev/zero of=$SDCARD bs=4M count=1 >> $TEMP_LOG 2>&1
    sync >> $TEMP_LOG 2>&1
    rm -Rf boot boot.tar.gz >> $TEMP_LOG 2>&1
    echo "Fuse card ..."
    wget http://odroid.in/guides/ubuntu-lfs/boot.tar.gz
    tar zxvf boot.tar.gz >> $TEMP_LOG 2>&1
    cd boot
    echo "      [*] Fusing media"
    chmod +x sd_fusing.sh  >> $TEMP_LOG 2>&1
    sudo ./sd_fusing.sh $SDCARD  >> $TEMP_LOG 2>&1
    cd $WORKDIR
    echo "      [*] Create partition schema"

    echo -e "o\nn\np\n1\n3072\n+64M\nn\np\n2\n135168\n\nt\n1\nc\np\nw\n" | sudo fdisk $SDCARD

    sudo partprobe  >> $TEMP_LOG 2>&1
    echo "      [*] Format partition and set attributes"

    sudo mkfs.vfat -n BOOT $SDCARD"1" >> $TEMP_LOG 2>&1
    sudo mkfs.ext4 -L ROOTFS $SDCARD"2" >> $TEMP_LOG 2>&1
    sudo tune2fs -o journal_data_writeback $SDCARD"2" >> $TEMP_LOG 2>&1
    sudo tune2fs -O ^has_journal $SDCARD"2" >> $TEMP_LOG 2>&1
    #set parition uuid for some kernel update scripts
    sudo tune2fs $SDCARD"2" -U e139ce78-9841-40fe-8823-96a304a09859 >> $TEMP_LOG 2>&1
    sudo e2fsck -f $SDCARD"2" >> $TEMP_LOG 2>&1
    sudo dosfslabel $SDCARD"1" BOOT >> $TEMP_LOG 2>&1
    sudo e2label $SDCARD"2" ROOTFS >> $TEMP_LOG 2>&1
    sudo dumpe2fs $SDCARD"2" | head >> $TEMP_LOG 2>&1
    echo "      [*] CARD prepared"

}


function BootstrapDebian()
{
    sudo mkdir -p -v $TARGET >> $TEMP_LOG 2>&1
    sudo mount -v -t ext4 $SDCARD"2" $TARGET >> $TEMP_LOG 2>&1
    echo "      [*] Bootstraping - this could take a while ..."
    sudo qemu-debootstrap --foreign --arch=$ARCH $DISTRIB $TARGET http://http.debian.net/debian >> $TEMP_LOG 2>&1
    sudo sh -c "echo 'T0:23:respawn:/sbin/getty -L ttySAC1 115200 vt100'>> $TARGET'etc/inittab'" >> $TEMP_LOG 2>&1
    sudo sh -c "echo 'ttySAC1'>> $TARGET'etc/securetty'" >> $TEMP_LOG 2>&1


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
    clear
    echo "Set password for ROOT:"
    sudo chroot $TARGET sh -c "passwd root"

    sudo wget -O $TARGET'usr/local/bin/odroid-utility.sh' https://raw.githubusercontent.com/mdrjr/odroid-utility/master/odroid-utility.sh
    sudo chmod +x $TARGET'usr/local/bin/odroid-utility.sh' >> $TEMP_LOG 2>&1

    sudo mount -v -o bind /dev $TARGET'dev'
    sudo mount -v -o bind /dev/pts $TARGET'dev/pts'
    sudo mount -v -o bind /sys $TARGET'sys'
    sudo mount -v -t proc proc $TARGET'proc'

    DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET apt-get update >> $TEMP_LOG 2>&1

    DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET apt-get install -y lsb-release initramfs-tools tzdata locales uboot-mkimage ntp sudo openssh-server curl bash-completion >> $TEMP_LOG 2>&1

    sudo cp $TARGET'etc/initram-fs/initramfs.conf.dpkg-new' $TARGET'etc/initram-fs/initramfs.conf'
    sudo cp $TARGET'etc/initram-fs/update-initramfs.conf.dpkg-new' $TARGET'etc/initram-fs/update-initramfs.conf'

}


function PutKernelAndFirmware_U3()
{
    echo "      [*] Install kernel and modules ..."
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
    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET tar xfv /root/odroidu2.tar >> $TEMP_LOG 2>&1

    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET xz -d /root/firmware.tar.xz
    LC_ALL=C LANGUAGE=C LANG=C sudo chroot $TARGET tar xfv /root/firmware.tar -C /lib/firmware/ >> $TEMP_LOG 2>&1



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

    sudo mv $TEMP_LOG $TARGET"root/odroid.build"

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
    mkdir -v -p $WORKDIR >> $TEMP_LOG
    cd $WORKDIR >> $TEMP_LOG
    CreatePartitions
    BootstrapDebian
    PutKernelAndFirmware_U3
    Finish
}

function initialize()
{

    echo "*** Debian for ODROID build ***" > $TEMP_LOG

    sudo apt-get install qemu-user-static debootstrap u-boot-tools dosfstools parted >> $TEMP_LOG

    TARGET_DEV=$(whiptail --backtitle "Debian for ODROID build script" --title "Select ODROID device" --menu "Choose an target ODROID device type" 15 40 5 \
    "ODROID-U3" "Target device: ODROID-U3." 3>&1 1>&2 2>&3)
    RET=$?
    if [ $RET -eq 1 ]; then
        exit 0
    fi

    echo "*** Selected target device: "$TARGET_DEV >> $TEMP_LOG

    export REMOVABLE_DEV=($(
        grep -Hv ^0$ /sys/block/*/removable |
        sed s/removable:.*$/device\\/uevent/ |
        xargs grep -H ^DRIVER=sd |
        sed s/device.uevent.*$/size/ |
        xargs grep -Hv ^0$ |
        cut -d / -f 4
    ))

    TARGET_MEDIA=$(for dev in ${REMOVABLE_DEV[@]} ;do
        echo $dev size:_$(
            sed -e s/\ *$//g </sys/block/$dev/size
        ) ;
    done)

    if [ -z "$TARGET_MEDIA" ]; then
        echo "No removable device found. exit."
        exit
    fi

    TARGET_MEDIA_DEV=$(whiptail --backtitle "Debian for ODROID build script" --title "Select media device" --menu "Choose an microSD or eMMC" 15 40 5 \
    $TARGET_MEDIA 3>&1 1>&2 2>&3)
    RET=$?
    if [ $RET -eq 1 ]; then
        exit 0
    fi


    export SDCARD="/dev/"$TARGET_MEDIA_DEV

    TARGETNAME=$(whiptail --title "Config hostname" --inputbox "Target device hostname" 10 60 ODROID 3>&1 1>&2 2>&3)
    RET=$?
    if [ $RET -eq 1 ]; then
        exit 0
    fi

    if (whiptail --backtitle "Debian for ODROID build script" --title "READ THIS !!!" --defaultno --yesno "ODROID U3 Debian build script. This tool are given as-is without warranty.\nAll data on $SDCARD will be erased. Do you want to proceed" 8 78) then
        ClearInstall
    else
        exit
    fi
}

initialize
