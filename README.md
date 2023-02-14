
# PiShrink #

PiShrink is a bash script that automatically shrink a pi image that will then resize to the max size of the SD card on boot. This will make putting the image back onto the SD card faster and the shrunk images will compress better.
In addition the shrunk image can be compressed with gzip and xz to create an even smaller image. Parallel compression of the image
using multiple cores is supported.

## Usage ##

```
Usage: $0 [-adhrsvzZ] imagefile.img [newimagefile.img]

  -s         Don't expand filesystem when image is booted the first time
  -v         Be verbose
  -r         Use advanced filesystem repair option if the normal one fails
  -z         Compress image after shrinking with gzip
  -Z         Compress image after shrinking with xz
  -a         Compress image in parallel using multiple cores
  -d         Write debug messages in a debug log file
```

If you specify the `newimagefile.img` parameter, the script will make a copy of `imagefile.img` and work off that. You will need enough space to make a full copy of the image to use that option.

* `-s` prevents automatic filesystem expansion on the images next boot
* `-v` enables more verbose output
* `-r` will attempt to repair the filesystem using additional options if the normal repair fails
* `-z` will compress the image after shrinking using gzip. `.gz` extension will be added to the filename.
* `-Z` will compress the image after shrinking using xz. `.xz` extension will be added to the filename.
* `-a` will use option -f9 for pigz and option -T0 for xz and compress in parallel.
* `-d` will create a logfile `pishrink.log` which may help for problem analysis.

Default options for compressors can be overwritten by defining PISHRINK_GZIP or PSHRINK_XZ environment variables for gzip and xz.

## Prerequisites ##

If you are running PiShrink in VirtualBox you will likely encounter an error if you
attempt to use VirtualBox's "Shared Folder" feature. You can copy the image you wish to
shrink on to the VM from a Shared Folder, but shrinking directctly from the Shared Folder
is know to cause issues.

If using Ubuntu, you will likely see an error about `e2fsck` being out of date and `metadata_csum`. The simplest fix for this is to use Ubuntu 16.10 and up, as it will save you a lot of hassle in the long run.

## Installation ##

```bash
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin
```

## Example ##

```bash
[user@localhost PiShrink]$ sudo pishrink.sh pi.img
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

## Contributing ##

If you find a bug please create an issue for it. If you would like a new feature added, you can create an issue for it but I can't promise that I will get to it.

Pull requests for new features and bug fixes are more than welcome!
