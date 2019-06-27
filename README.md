### Acknowledgment
overlayRoot is based on a script published by Pascal Sutter on the Raspberry Forums. 
https://www.raspberrypi.org/forums/viewtopic.php?f=66&t=173063&p=1106694#p1106694
### Default operation

* By default overlayRoot mounts your root file system read only and overlays a tmpfs ramdisk on top of that.
All updates to your system will be lost on power off.  Optionally you can specify some media
to retain updates across reboots.

* Root is mounted at `/ro` and tmpfs at `/rw` 

###Install
* Copy this directory to a directory on your pi.  Change to that directory and run `sudo bash install`.  
```bash
git clone https://github.com/marklister/overlayRoot.git
cd overlayRoot
sudo bash install

```

* Edit `/etc/overlayRoot.conf`:  to suit your preferences. OverlayRoot should work as expected with everything 
set to default.  Options are documented in `overlayRoot.conf`

* Recommend disabling swapping before using overlayRoot: 
```bash
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo update-rc.d dphys-swapfile remove
```

### System Maintainence

#### Disable overlayRoot entirely

* To disable rootOverlay you can jumper the pin specified in the .conf file (default gpio 4) to ground.  

* Alternatively edit your 
`cmdline.txt` file and place `init=/sbin/overlayRoot.sh` on a separate line.  
 
#### Remount

* You can remount the root to make changes: `sudo mount -o remount,rw /ro`

#### Chroot

* The chroot command might allow you to install software without reboot:
```bash
pi@raspberrypi:~ $ sudo mount -o remount,rw /ro
pi@raspberrypi:~ $ sudo chroot /ro
root@raspberrypi:/# apt update
Get:1 http://archive.raspberrypi.org/debian buster InRelease [25.1 kB]                                             
Get:2 http://raspbian.raspberrypi.org/raspbian buster InRelease [15.0 kB]                                          
Get:3 http://raspbian.raspberrypi.org/raspbian buster/main armhf Packages [13.0 MB]
Get:4 http://archive.raspberrypi.org/debian buster/main armhf Packages [201 kB]                                          
...                                                            
root@raspberrypi:/# exit
exit
pi@raspberrypi:~ $ 

```

### Persistent media

* Enable persistent media by placing an entry in your `/etc/fstab`. Edit 
`/ro/etc/fstab` if rootOvelay is active. 

```bash
proc                                          /proc          proc    defaults                 0       0
PARTUUID=78a96f0b-01                          /boot          vfat    defaults                 0       2
UUID="d065e631-6b9d-48c0-a8fe-e663b42828e0"   /              ext4    defaults,noatime         0       1
UUID="cf3aa597-5e28-44b2-8dfb-8c21d7312589"   /mnt/root-rw   ext4    defaults,noatime,nofail  0       1
```
* To obtain UUIDs use the `blkid` command.

### Limitations

* PARTUUIDs are not supported.  Use UUIDs instead.
* dphys-swapfile doesn't start on Raspian Buster


 
