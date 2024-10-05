
# PiShrink #

PiShrink is a bash script that automatically shrink a pi image that will then resize to the max size of the SD card on boot. This will make putting the image back onto the SD card faster and the shrunk images will compress better.
In addition the shrunk image can be compressed with gzip and xz to create an even smaller image. Parallel compression of the image
using multiple cores is supported.

## Usage ##

```text
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
shrink on to the VM from a Shared Folder, but shrinking directly from the Shared Folder
is know to cause issues.

If using Ubuntu, you will likely see an error about `e2fsck` being out of date and `metadata_csum`. The simplest fix for this is to use Ubuntu 16.10 and up, as it will save you a lot of hassle in the long run.

PiShrink will shrink the last partition of your image. If that partition is not ext2, ext3, or ext4 it will not be able to shrink your image.
If the last partition is not the root filesystem partition, auto resizing will not run on boot.
If you want to use auto resizing on a distro using Systemd, you should ensure you [Enabled /etc/rc.local Compatibility](https://www.linuxbabe.com/linux-server/how-to-enable-etcrc-local-with-systemd).

## Installation ##

### Linux Instructions ###

If you are on Debian/Ubuntu you can install all the packages you would need by running: `sudo apt update && sudo apt install -y wget parted gzip pigz xz-utils udev e2fsprogs`

Run the block below to install PiShrink onto your system.

```bash
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin
```

### Windows Instructions ###

PiShrink can be ran on Windows using [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/about) (WSL 2).

1. In an Administrator command prompt run `wsl --install -d Debian`. You will likely need to reboot after. Please check [Microsoft's documentation](https://learn.microsoft.com/en-us/windows/wsl/install) if you run into issues.
2. Open the `Debian` app from your start menu.
3. Run `sudo apt update && sudo apt install -y wget parted gzip pigz xz-utils udev e2fsprogs`
4. Go to the Linux Instructions section above, do that and you're good to go! Your C:\ drive is mounted at /mnt/c/

### MacOS Instructions ###

These instructions were sourced from the community and should work on Intel and M1 Macs.

1. [Installer Docker](https://docs.docker.com/docker-for-mac/install/).
2. `cd` in the pishrink directory you downloaded/cloned.
3. Build the container by running `docker build -t pishrink .`
4. Create an alias to run PiShrink `echo "alias pishrink='docker run -it --rm --platform linux/amd64 --privileged=true -v $(pwd):/workdir pishrink'" >> ~/.bashrc && source ~/.bashrc`

You can now run the `pishrink` command as normal to shrink your images.

***Please Note:*** You MUST change directory into the images folder for this command to work. The command mounts your current working directory into the container so absolute file paths will not work. Relative paths should work just fine as long as they are below your current directory.

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
