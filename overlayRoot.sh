#!/bin/sh
#  Read-only Root-FS for Raspian using overlayfs
#  Version 1.1
#
#  Version History:
#  1.0: initial release
#  1.1: adopted new fstab style with PARTUUID. the script will now look for a /dev/xyz definiton first 
#       (old raspbian), if that is not found, it will look for a partition with LABEL=rootfs, if that
#       is not found it look for a PARTUUID string in fstab for / and convert that to a device name
#       using the blkid command.
#
#  1.2: Modified the mount point to /mnt/root-rw and if a partition is mounted there (an fstab entry exists)
#       already use that partition as the upper.  Allows one to offload writes to some other media and 
#       possibly write back the changes periodically to the lower.  Note when running in this mode
#       a swapfile may be a reasonable idea.
#
#  Created 2017 by Pascal Suter @ DALCO AG, Switzerland to work on Raspian as custom init script
#  (raspbian does not use an initramfs on boot)
#  Modifications listed as 1.2 Mark Lister: github.com/marklister
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see
#    <http://www.gnu.org/licenses/>.
#
#
#  Tested with Raspbian mini, 2018-10-09
#
#  This script will mount the root filesystem read-only and overlay it with a temporary tempfs 
#  which is read-write mounted. This is done using the overlayFS which is part of the linux kernel 
#  since version 3.18. 
#  when this script is in use, all changes made to anywhere in the root filesystem mount will be lost 
#  upon reboot of the system. The SD card will only be accessed as read-only drive, which significantly
#  helps to prolong its life and prevent filesystem coruption in environments where the system is usually
#  not shut down properly 
#
#  Install: 
#  copy this script to /sbin/overlayRoot.sh, make it executable and add "init=/sbin/overlayRoot.sh" to the 
#  cmdline.txt file in the raspbian image's boot partition. 
#  I strongly recommend to disable swapping before using this. it will work with swap but that just does 
#  not make sens as the swap file will be stored in the tempfs which again resides in the ram.
#  run these commands on the booted raspberry pi BEFORE you set the init=/sbin/overlayRoot.sh boot option:
#  sudo dphys-swapfile swapoff
#  sudo dphys-swapfile uninstall
#  sudo update-rc.d dphys-swapfile remove
#
#  To install software, run upgrades and do other changes to the raspberry setup, simply remove the init= 
#  entry from the cmdline.txt file and reboot, make the changes, add the init= entry and reboot once more. 

fail(){
  echo -e "Init FAIL: $1"
  # if this appears to hang your machine make sure your active console is the last 'console=' entry 
  # in /boot/cmdline.txt
  /bin/bash
}

info(){
  echo -e "Init Info: $1"
}

# Stolen from usr/share/initramfs-tools/scripts/functions 

# Find a specific fstab entry
# $1=mountpoint
# $2=fstype (optional)
# returns 0 on success, 1 on failure (not found or no fstab)
read_fstab_entry() {
  # Not found by default.
  found=1
  for file in /etc/fstab; do
    if [ -f "$file" ]; then
      while read MNT_FSNAME MNT_DIR MNT_TYPE MNT_OPTS MNT_FREQ MNT_PASS MNT_JUNK; do
        case "$MNT_FSNAME" in
          ""|\#*)
          continue;
          ;;
        esac
        if [ "$MNT_DIR" = "$1" ]; then
          if [ -n "$2" ]; then
            [ "$MNT_TYPE" = "$2" ] || continue;
          fi
          found=0
          break 2
        fi
      done < "$file"
    fi
  done

  return $found
}

# Mount point for writable drive
RW="/mnt/root-rw"

# load module
modprobe overlay
if [ $? -ne 0 ]; then
    fail "ERROR: missing overlay kernel module"
fi
# mount /proc
mount -t proc proc /proc
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount proc"
fi
# create a writable fs to then create our mountpoints 
mount -t tmpfs inittemp /mnt
if [ $? -ne 0 ]; then
    fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"
fi
mkdir /mnt/lower
mkdir $RW
if read_fstab_entry $RW; then 
  mount  $RW
  if [ $? -ne 0 ]; then
      fail "ERROR: running mount $RW"
  fi
else
  mount -t tmpfs tmp-root-rw $RW
  if [ $? -ne 0 ]; then
      fail "ERROR: could not create tempfs for upper filesystem"
  fi
fi
mkdir $RW/upper
mkdir $RW/work
mkdir /mnt/newroot
# mount root filesystem readonly 
rootDev=`awk '$2 == "/" {print $1}' /etc/fstab`
rootMountOpt=`awk '$2 == "/" {print $4}' /etc/fstab`
rootFsType=`awk '$2 == "/" {print $3}' /etc/fstab`
echo "check if we can locate the root device based on fstab"
blkid $rootDev
if [ $? -gt 0 ]; then
    echo "no success, try if a filesystem with label 'rootfs' is avaialble"
    rootDevFstab=$rootDev
    rootDev=`blkid -L "rootfs"`
    if [ $? -gt 0 ]; then
        echo "no luck either, try to further parse fstab's root device definition"
        echo "try if fstab contains a PARTUUID definition"
        echo "$rootDevFstab" | grep 'PARTUUID=\(.*\)-\([0-9]\{2\}\)'
        if [ $? -gt 0 ]; then 
            fail "could not find a root filesystem device in fstab. Make sure that fstab contains a device definition or a PARTUUID entry for / or that the root filesystem has a label 'rootfs' assigned to it"
        fi
        device=""
        partition=""
        eval `echo "$rootDevFstab" | sed -e 's/PARTUUID=\(.*\)-\([0-9]\{2\}\)/device=\1;partition=\2/'`
        rootDev=`blkid -t "PTUUID=$device" | awk -F : '{print $1}'`p$(($partition))
        blkid $rootDev
        if [ $? -gt 0 ]; then
            fail "The PARTUUID entry in fstab could not be converted into a valid device name. Make sure that fstab contains a device definition or a PARTUUID entry for / or that the root filesystem has a label 'rootfs' assigned to it"
        fi
    fi
fi
mount -t ${rootFsType} -o ${rootMountOpt},ro ${rootDev} /mnt/lower
if [ $? -ne 0 ]; then
    fail "ERROR: could not ro-mount original root partition"
fi
mount -t overlay -o lowerdir=/mnt/lower,upperdir=$RW/upper,workdir=$RW/work overlayfs-root /mnt/newroot
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount overlayFS"
fi
# create mountpoints inside the new root filesystem-overlay
mkdir /mnt/newroot/ro
mkdir /mnt/newroot/rw
# remove root mount from fstab (this is already a non-permanent modification)
grep -v "$rootDev" /mnt/lower/etc/fstab > /mnt/newroot/etc/fstab
echo "#the original root mount has been removed by overlayRoot.sh" >> /mnt/newroot/etc/fstab
echo "#this is only a temporary modification, the original fstab" >> /mnt/newroot/etc/fstab
echo "#stored on the disk can be found in /ro/etc/fstab" >> /mnt/newroot/etc/fstab
# change to the new overlay root
cd /mnt/newroot
pivot_root . mnt
exec chroot . sh -c "$(cat <<END
# move ro and rw mounts to the new root
mount --move /mnt/mnt/lower/ /ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move ro-root into newroot"
    /bin/bash
fi
mount --move /mnt/$RW /rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move tempfs rw mount into newroot"
    /bin/bash
fi
# unmount unneeded mounts so we can unmout the old readonly root
umount /mnt/mnt
umount /mnt/proc
umount /mnt/dev
umount /mnt
# continue with regular init
exec /sbin/init
END
)"
