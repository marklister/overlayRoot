#!/usr/bin/env bash
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
#       You should probably specify 'defaults,noatime,nofail' on the mount options for the writeable media.
#       Then you won't hang if the media doesn't mount.
#
#       I couldn't get partuuids to work, they seem to be available only after boot.  Try uuids or plain devices
#
#       Resolution by partition label is disabled.  It's very easy to mess this up.  At the end of the day
#       the entire purpose of fstab is to mount the correct devices at the correct places.
#
#       Support for a jumper on gpio 4 which disables the script if you ground the pin.  Install wiringpi if
#       you want to use this.
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
#  If you want writable media edit your fstab so the the correct media is mounted at /mnt/root-rw.
#  PARTUUID entries don't work at the moment (possibly a Debian bug) so use UUIDs or plain devices.
#  Be careful you are not updating a non persistent fstab!  Only the one on actual root works.
#
#  To install software, run upgrades and do other changes to the raspberry setup, simply remove the init=
#  entry from the cmdline.txt file and reboot, make the changes, add the init= entry and reboot once more.

    quiet(){
        return 1
    }
    fail(){
      echo -e "[FAIL:overlay] $1"
      # if this appears to hang your machine make sure your active console is the last 'console=' entry
      # in /boot/cmdline.txt
      /bin/bash
    }

    info(){
      if quiet; then return; fi
      echo -e "[INFO:overlay] $1"
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
      info "fstab lookup of $1 $2 returned $MNT_FSNAME $MNT_DIR $MNT_TYPE $MNT_OPTS $MNT_FREQ $MNT_PASS $MNT_JUNK"
      return $found
    }

    #Wait for a device to become available
    # $1 device
    # $2 timeout
    await_device() {
        count=0
        if [ -z $2 ]; then TIMEOUT=60; else TIMEOUT=$2; fi
        result=1
        while [ $count -lt $TIMEOUT ];
        do
            info "Waiting for device $1 $count";
            test -e $1
            if [ $? -eq 0 ]; then
                info "$1 appeared after $count seconds";
                result=0
                break;
            fi
            sleep 1;
            ((count++))
        done
        return $result
    }

    # Resolve a device from a fstab type entry eg /dev/sda1 or UUID= or PARTUUID=
    # $1 the entry to resolve
    # This apears to be unreliable, and I see root is resolved by label as well
    # Returns $DEV

    resolve_device() {

        DEV="$1"
        if $(echo "$DEV" | grep -q "^/dev/"); then
            info "No resolution necessary, device $DEV was available directly"
        elif $(echo "$1" | grep -q '='); then
            info "looking up $1 by a partuuid or uuid"
            DEV="$(blkid -l -t $1 -o device)"
            if [ ! -z "$DEV" ]; then
              info "Resolved device $DEV from UUID/PARTUUID $1"
            fi
        fi
        info "final resolution is $DEV"
        return $(echo "$DEV" | grep -q  "^/dev/")
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

    gpio mode 4 up  # activate pull up resistor  ground is just above pin 4

    if [[ $(gpio read 4) = 0 ]]; then
        info "aborting overlayRoot due to jumper"
        exec /sbin/init
        exit 0
    else
        info "No jumper -- running overlay root"
    fi


    # create a writable fs to then create our mountpoints
    mount -t tmpfs inittemp /mnt
    if [ $? -ne 0 ]; then
        fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"
    fi

    mkdir /mnt/lower
    mkdir $RW
    if read_fstab_entry $RW; then
        info "found fstab entry for $RW"
        # Things don't go well if usb is not up or fsck is being performed
        # kludge -- wait for /dev/sda1

        await_device "/dev/sda1"  20  #Wait a generous amount of time for first device
        if ! resolve_device "$MNT_FSNAME" "root-rw"; then
            info "No device found for $RW going to wait for /dev/sdb1..."
            DEV="/dev/sdb1"
        fi

        #This time we are hopefully waiting for the actual device not /dev/sda1
        if await_device "$DEV" 5; then
            info "$DEV device found"
        else
            info "$DEV device not found"
        fi

        #Retry the lookup

        if ! resolve_device "$MNT_FSNAME" "root-rw"; then
            info "Still no device found for $RW"
        fi

        if [ -z "$DEV" ]; then
            info "Couldn't resolve the RW media, mounting a tmpfs instead"
            info "You should test for this and send an alert.  You could grep 'emergency' in /proc/mounts"
            mount -t tmpfs emergency-root-rw $RW
            if [ $? -ne 0 ]; then
              fail "ERROR: could not create emergency tempfs for upper filesystem"
            fi
        elif  ! $(test -e "$DEV"); then
            info "Couldn't locate the RW media on $DEV, mounting a tmpfs instead"
            info "You should test for this and send an alert.  You could grep 'emergency' in /proc/mounts"
            mount -t tmpfs emergency-root-rw $RW
            if [ $? -ne 0 ]; then
              fail "ERROR: could not create emergency tempfs for upper filesystem"
            fi
        else
            info "Running mount -t $MNT_TYPE -o $MNT_OPTS $DEV $RW"
            mount -t $MNT_TYPE -o $MNT_OPTS $DEV $RW
            if [ $? -ne 0 ]; then
                fail "ERROR: could not mount $DEV options: $MNT_OPTS on $RW for upper filesystem"
            fi
        fi
    else
        info "No fstab entry, mounting tmpfs"
        mount -t tmpfs tmp-root-rw $RW
        if [ $? -ne 0 ]; then
          fail "ERROR: could not create tempfs for upper filesystem"
        fi
    fi

    mkdir -p $RW/upper
    mkdir -p $RW/work
    mkdir /mnt/newroot
    # mount root filesystem readonly

    read_fstab_entry "/"
    if ! resolve_device $MNT_FSNAME "rootfs"; then
        fail "Can't resolve root device from $MNT_FSNAME or label rootfs.  Try changing entry to UUID or plain device"
    fi
    info "Mounting ro root: mount -t $MNT_TYPE -o $MNT_OPTS,ro $DEV /mnt/lower"
    mount -t $MNT_TYPE -o $MNT_OPTS,ro $DEV /mnt/lower

    info "Mounting overlay: mount -t overlay -o lowerdir=/mnt/lower,upperdir=$RW/upper,workdir=$RW/work overlayfs-root /mnt/newroot"
    mount -t overlay -o lowerdir=/mnt/lower,upperdir=$RW/upper,workdir=$RW/work overlayfs-root /mnt/newroot
    if [ $? -ne 0 ]; then
        fail "ERROR: could not mount overlayFS"
    fi
    # create mountpoints inside the new root filesystem-overlay
    mkdir -p /mnt/newroot/ro
    mkdir -p /mnt/newroot/rw
    # remove root mount from fstab (this is already a non-permanent modification)
    grep -v "$DEV" /mnt/lower/etc/fstab > /mnt/newroot/etc/fstab
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