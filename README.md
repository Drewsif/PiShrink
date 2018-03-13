# PiShrink-macOS#
This is a port of PiShrink bash script for Linux to run under macOS.

PiShrink [https://github.com/Drewsif/PiShrink](https://github.com/Drewsif/PiShrink) is a bash script that automatically shrinks a pi image. This will make putting the image back onto the SD card faster and the shrunk images will compress better.

Besides the original script it uses a few utils for the ext2/3/4 filesystem. All of these tools can be easily build by running the provided helper scripts in this repository. For mor information see below.

## Usage ##
`pishrink.sh imagefile.img [newimagefile.img]`

If you specify the `newimagefile.img` parameter, the script will make a copy of `imagefile.img` and work off that. You will need enough space to make a full copy of the image to use that option.

## Prerequisites ##
If you are trying to shrink a [NOOBS](https://github.com/raspberrypi/noobs) image it will likely fail. This is due to [NOOBS paritioning](https://github.com/raspberrypi/noobs/wiki/NOOBS-partitioning-explained) being significantly different than Raspian's. Hopefully PiShrink will be able to support NOOBS in the near future.


## Installation ##
Since you are using a RaspberryPi I'm quite sure, that you've already installed Xcode and the Xcode commandline tools. If not, please do so.

Then download the zip archive, uncompress it, run make and sudo amke install. Here are the corresponding commands:

```bash
curl -LO https://github.com/lisanet/PiShrink-macOS/archive/master.zip
unzip master
cd PiShrink-macOS-master
make
sudo make install
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
