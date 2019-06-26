###Install
1. Copy this directory to a directory on your pi.  Change to that directory and run `sudo bash install`
```bash
git clone https://github.com/marklister/overlayRoot.git
cd overlayRoot
sudo bash install

```
1. Edit /etc/overlayRoot.conf:  to suit your preferences. OverlayRoot should work as expected with everything 
set to default.

1. OverlayRoot should work in 
    as a read only root filesystem with a tmpfs overlay without any editing of /etc/fstab.  Edit your fstab if you 
    require a persistent RW overlay or want to identify partitions by UUID. 
    Use `blkid` to display UUIDs.   

1. Recommend disabling swapping before using overlayRoot. 
```bash
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo update-rc.d dphys-swapfile remove
```
4. To disable rootOverlay you can jumper the pin specified in the .conf file (default gpio 4) to ground.  Alternatively edit your 
cmdline.txt file and place init=/sbin/overlayRoot.sh on a separate line.  
 
5. IF you want writable media edit your fstab so the the correct media is mounted at /mnt/root-rw.
 PARTUUID entries don't work at the moment (possibly a Debian bug) so use UUIDs or plain devices.
 Be careful you are not updating a non-persistent fstab.  Only the one on actual root works.
 You can mount anything at /mnt/root-rw the script is not opiniated.  The nofail option is recommended if you want to avoid
 a mount failure preventing your pi from booting.

```bash
proc                                          /proc           proc    defaults          0       0
PARTUUID=78a96f0b-01                          /boot           vfat    defaults          0       2
UUID="d065e631-6b9d-48c0-a8fe-e663b42828e0"   /               ext4    defaults,noatime  0       1
UUID="cf3aa597-5e28-44b2-8dfb-8c21d7312589"   /mnt/root-rw,nofail    ext4    defaults,noatime  0       1
```
  To install software, run upgrades and do other changes to the raspberry setup, simply remove the init=
  entry from the cmdline.txt file and reboot, make the changes, add the init= entry and reboot once more.  
  
  Alternatively install a jumper to ground on the specified pin (default gpio 4) to
  disable overlayRoot.
  
 