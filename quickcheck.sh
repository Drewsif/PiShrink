#!/usr/bin/env bash

function info() {
	echo "$SCRIPTNAME: $1"
}

function error() {
	echo -n "$SCRIPTNAME: ERROR occurred in line $1: "
	shift
	echo "$@"
}

function fixPARTUUID()
{
    # Parameters 
        # $1 (Required) Name of image file
        # $2 (Optional) If no fixup is desired, parameter 2 should be "NOFIX" (any other value is ignored)
        # $3 (Optional) If debugging is desired, parameter 3 should be "DEBUG" (any other value is ignored)

    # Check that image to see if it is supported:
    #   Must have 2 partitions
    #   Must contain the following 2 files
    #       Partition 1: cmdline.txt 
    #       Partition 2: /etc/fstab
    #   PARTUUID of device partitions must appropriately correct in the above files according to the PARTUUIDs discovered
    #   If the PARTUUIDs of the files aren't correct, they are corrected unless "NOFIX" is supplied for $2

    # Return Codes:
    #   0 - Partition supported and PARTUUIDs are correct
    #   1 - Partition supported and PARTUUIDs were corrected 
    #   2 - Partition supported and needs fix but NOFIX was specified
    #   9 - Partition type not supported

    # Sets these global variables:
    #   devdisk         - the block loopback device holding the partitions (e.g. loop0)
    #   devpart1        - the device name of partition 1 (e.g. loop0p1)
    #   devpart2        - the device name of partition 2 (e.g. loop0p2)
    #   Note that it is possible to have more devpart variables if the block device hase more than 2 partitions
    #   numparts        - the number of partitions discovered
    #   UUIDpart1       - PARTUUID of partition 1 
    #   UUIDpart2       - PARTUUID of partition 2 
    #   UUIDcmdlinep2   - PARTUUID of partition 2, according to partition 1's cmdline.txt file
    #   UUIDfstabp1     - PARTUUID of partition 1, according to partition 2's /etc/fstab file
    #   UUIDfstabp2     - PARTUUID of partition 2, according to partition 2's /etc/fstab file 

    i=0
    numparts=0

    # set cleanup action
    trap fixUUIDCleanup EXIT

    # mount image to block device
    #echo Mounting image $1
    loopimg=$(losetup -Pf --show $1)
    udevadm settle
    
    info "Beginning PARTUUID checks on block device $loopimg"
    if [ -z "$1" ]
    then 
        error $LINENO "fixPARTUUID requires a parameter"
        error $LINENO "example call fixpartUUID <image file location>"
        return 9
    fi
    # Get names of block device and partitions
    while IFS= read -r line; do
        if (( i==0 )); then 
            devdisk=$line                       # Device holding the partitions
        else                                    # It's a partition 
            devpartname="devpart$i"             # Append partition number to dynamic variable
            declare -g "$devpartname"=$line     # Assign a value to the dynamic variable
        fi
        numparts=$i;
        ((i++))
    done < <(lsblk -ln -o NAME $loopimg)

    # Only support 2 partitions
    if [ $numparts -ne 2 ]; 
    then 
        error $LINENO "CANNOT FIX: This script only supports 2 partitions, this device has $numparts partitions"
        return 9 
    fi

    # mount files to inspect and update PARTUUIDs
    mountprefix="/mnt/__UUID"
    mkdir ${mountprefix}Check1
    mkdir ${mountprefix}Check2
    mount "/dev/$devpart1" "${mountprefix}Check1"
    mount "/dev/$devpart2" "${mountprefix}Check2"
    checkfile1="${mountprefix}Check1/cmdline.txt"
    checkfile2="${mountprefix}Check2/etc/fstab"
    # echo "Checkfile1 is " $checkfile1
    # echo "Checkfile2 is " $checkfile2
    if [[ ! -f "$checkfile1" ||  ! -f "$checkfile2" ]];  # files need to be present
    then
        error $LINENO "CANNOT FIX: Partition not supported because correct files are not present:"
        info "-  bootpartiton must have cmdline.txt"
        info  "-  file system partition must have /etc/fstab"
        returncode=9
    else                                                  # Files are present, let's check them
        UUIDpart1=$(lsblk -no PARTUUID /dev/${devpart1})
        UUIDpart2=$(lsblk -no PARTUUID /dev/${devpart2})
         #do sed stuff
        UUIDcmdlinep2=$(sed -n 's/.*PARTUUID=\([^ ]*\).*/\1/p' $checkfile1)
        UUIDfstabp1=$(sed -n '2s/.*PARTUUID=\([^ ]*\).*/\1/p' $checkfile2)
        UUIDfstabp2=$(sed -n '3s/.*PARTUUID=\([^ ]*\).*/\1/p' $checkfile2)

        # Check what's in the files vs what was detected
        if  [ "$UUIDpart2" = "$UUIDcmdlinep2" ] && \
            [ "$UUIDpart1" = "$UUIDfstabp1" ] && \
            [ "$UUIDpart2" = "$UUIDfstabp2" ]
        then
            echo "Image checks OK, no fixup required"
            returncode=0
        else
            info "Image needs correction to boot successfully"
            info "PARTUUID of partition 1 is: $UUIDpart1 but according to /etc/fstab, the value is: $UUIDfstabp1"
            info "PARTUUID of partition 1 is: $UUIDpart2 but according to /etc/fstab, the value is: $UUIDfstabp2"
            info "PARTUUID of partition 2 is: $UUIDpart2 but according to cmdline.txt, the value is: $UUIDcmdlinep2"
            if [ "$2" = "NOFIX" ] 
            then
            info "----- NOFIX specified, skipping fix -----"
            returncode=2
            else
            info "Fixing image"
            sed  -i "1s|PARTUUID=$UUIDcmdlinep2|PARTUUID=$UUIDpart2|" $checkfile1          # fix cmdline.txt
            sed  -i "2s|PARTUUID=$UUIDfstabp1|PARTUUID=$UUIDpart1|" $checkfile2            # fix /etc/fstab
            sed  -i "3s|PARTUUID=$UUIDfstabp2|PARTUUID=$UUIDpart2|" $checkfile2            # fix /etc/fstab
            info "Image fix complete!!"
            fi
            returncode=1
        fi
    fi
    #cleanup
    # fixUUIDCleanup

    info "Image check complete"
    if [ $3 = "DEBUG" ]
    then
        echo -e "\n************ Debugging statements follow ****************
        "
        echo "Return code is $returncode"
        echo "The block device is $devdisk"
        echo -e "\nThere are $numparts partitions"
        echo "devpart1 = $devpart1"
        echo "devbart2 = $devpart2"
        echo -e "\nPARTUUIDs"
        echo "PARTUUID of partition 1 is: $UUIDpart1"
        echo "PARTUUID of partition 2 is: $UUIDpart2"
        echo "PARTUUID of partition 2, according to partition 1's cmdline.txt file: $UUIDcmdlinep2"
        echo "PARTUUID of partition 1, according to partition 2's /etc/fstab file: $UUIDfstabp1"
        echo "PARTUUID of partition 2, according to partition 2's /etc/fstab file: $UUIDfstabp2"
    fi
    
    return $returncode
}

fixUUIDCleanup () {
    #cleanup
    umount ${mountprefix}Check1 >&/dev/null
    umount ${mountprefix}Check2 >&/dev/null
    rmdir ${mountprefix}* >&/dev/null
    losetup -d $loopimg >&/dev/null
  
}

# ************************ Mainline **********************

img=$1
SCRIPTNAME=$(basename "$0")
if  [ $EUID -ne 0 ] 
then
    info "Must be sudo to run this"
    exit 1
fi
if [ -z $1 ] || [ ! -f $1 ]
then
    info "Enter a valid image file name as the first parameter"
    exit 1
fi
# Just check the image given as a file name
fixPARTUUID $img "NOFIX" "NODEBUG"
