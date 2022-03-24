
# PiShrink #

PiShrink is a bash script that automatically shrink a pi image that will then resize to the max size of the SD card on boot. This will make putting the image back onto the SD card faster and the shrunk images will compress better.
In addition the shrunk image can be compressed with gzip and xz to create an even smaller image. Parallel compression of the image
using multiple cores is supported.

## Usage ##

```txt
Usage: pishrink.sh [-adhrspvzZ] file [newfile]
Shrink and/or compress the given Linux image.
Options:
-d         Write debug messages to pishrink.log in the working directory.
-e n       Add an extra n (default 100) megabytes to the shrunk image.
-l n       Limit size to expand the rootfs during first boot. See argument of the size2fs command. Ex: "-l 4.5G".
-p         Purge redudant files (logs, apt archives, dhcp leases...).
-r         Use advanced filesystem repair option if the normal one fails
-n         Don't expand filesystem when image is booted the first time
-z         Compress image after shrinking with gzip
-Z         Compress image after shrinking with xz
-a         Compress image in parallel using multiple cores
-v         Be verbose
```

If you specify the `newimagefile.img` parameter, the script will make a copy of `imagefile.img` and work off that. You will need enough space to make a full copy of the image to use that option.
