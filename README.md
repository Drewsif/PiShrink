# PiShrink #
PiShrink is a bash script that automatically shrink a pi image that will then resize to the max size of the SD card on boot. This will make putting the image back onto the SD card faster and the shrunk images will compress better. The script can also work directly from the SD card reader device.

`Usage: ./pishrink [-s] [-i] imagefile.img [newimagefile.img]`
        ./pishrink [-s] [-i] /dev/sd_device [newimagefile.img]`

If the `-s` option is given the script will skip the autoexpanding part of the process.  If you specify the `newimagefile.img` parameter, the script will make a copy of `imagefile.img` and work off that. You will need enough space to make a full copy of the image to use that option.
If a device file (e.g. /dev/mmcblk0) is given as parameter, it will shrink the image directly on the SD card. If the `-i` option is given the script will first shrink in place, then prepare a copy. This is especially useful when the first parameter is a device file and space is limited.

## Example ##
```bash
[user@localhost PiShrink]$ sudo ./pishrink.sh pi.img
e2fsck 1.42.9 (28-Dec-2013)
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
/dev/loop1: 88262/1929536 files (0.2% non-contiguous), 842728/7717632 blocks
resize2fs 1.42.9 (28-Dec-2013)
resize2fs 1.42.9 (28-Dec-2013)
Resizing the filesystem on /dev/loop1 to 773603 (4k) blocks.
Begin pass 2 (max = 100387)
Relocating blocks             XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Begin pass 3 (max = 236)
Scanning inode table          XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Begin pass 4 (max = 7348)
Updating inode references     XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
The filesystem on /dev/loop1 is now 773603 blocks long.

Shrunk pi.img from 30G to 3.1G
```
## Example: copying shrinking directly from SD ##

[user@localhost PiShrink]$ sudo  ./pishrink.sh /dev/mmcblk0 pi.img
Copying /dev/mmcblk0 to pi.img...
30528+0 records in
30528+0 records out
32010928128 bytes (32 GB, 30 GiB) copied, 587,625 s, 54,5 MB/s
Creating new /etc/rc.local
e2fsck 1.42.13 (17-May-2015)
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
/dev/loop0: 127844/1915424 files (0.1% non-contiguous), 1743616/7798016 blocks
resize2fs 1.42.13 (17-May-2015)
resize2fs 1.42.13 (17-May-2015)
Resizing the filesystem on /dev/loop0 to 2187260 (4k) blocks.
Begin pass 3 (max = 238)
Scanning inode table          XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
The filesystem on /dev/loop0 is now 2187260 (4k) blocks long.
Shrunk pi.img from 30G to 8,5G

## Example: shrinking directly on SD ad copying ##



## Contributing ##
If you find a bug please create an issue for it. If you would like a new feature added, you can create an issue for it but I can't promise that I will get to it.

Pull requests for new features and bug fixes are more than welcome!
