#!/bin/bash

function cleanup() {
  if losetup $loopback &>/dev/null; then
	losetup -d "$loopback"
  fi
}

usage() { echo "Usage: $0 [-s] imagefile.img [newimagefile.img]"; exit -1; }

should_skip_autoexpand=false

while getopts ":s" opt; do
  case "${opt}" in
    s) should_skip_autoexpand=true ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

#Args
img="$1"

#Usage checks
if [[ -z "$img" ]]; then
  usage
fi
if [[ ! -f "$img" ]]; then
  echo "ERROR: $img is not a file..."
  exit -2
fi
if (( EUID != 0 )); then
  echo "ERROR: You need to be running as root."
  exit -3
fi

#Check that what we need is installed
for command in parted losetup tune2fs md5sum e2fsck resize2fs; do
  which $command 2>&1 >/dev/null
  if (( $? != 0 )); then
    echo "ERROR: $command is not installed."
    exit -4
  fi
done

#Copy to new file if requested
if [ -n "$2" ]; then
  echo "Copying $1 to $2..."
  cp --reflink=auto --sparse=always "$1" "$2"
  if (( $? != 0 )); then
    echo "ERROR: Could not copy file..."
    exit -5
  fi
  old_owner=$(stat -c %u:%g "$1")
  chown $old_owner "$2"
  img="$2"
fi

# cleanup at script exit
trap cleanup ERR EXIT

#Gather info
beforesize=$(ls -lh "$img" | cut -d ' ' -f 5)
parted_output=$(parted -ms "$img" unit B print | tail -n 1)
partnum=$(echo "$parted_output" | cut -d ':' -f 1)
partstart=$(echo "$parted_output" | cut -d ':' -f 2 | tr -d 'B')
loopback=$(losetup -f --show -o $partstart "$img")
tune2fs_output=$(tune2fs -l "$loopback")
currentsize=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
blocksize=$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)

#Check if we should make pi expand rootfs on next boot
if [ "$should_skip_autoexpand" = false ]; then
  #Make pi expand rootfs on next boot
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"

  if [ $(md5sum "$mountdir/etc/rc.local" | cut -d ' ' -f 1) != "0542054e9ff2d2e0507ea1ffe7d4fc87" ]; then
    echo "Creating new /etc/rc.local"
    mv "$mountdir/etc/rc.local" "$mountdir/etc/rc.local.bak"
    #####Do not touch the following lines#####
cat <<\EOF1 > "$mountdir/etc/rc.local"
#!/bin/bash
do_expand_rootfs() {
  ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')

  PART_NUM=${ROOT_PART#mmcblk0p}
  if [ "$PART_NUM" = "$ROOT_PART" ]; then
    echo "$ROOT_PART is not an SD card. Don't know how to expand"
    return 0
  fi

  # Get the starting offset of the root partition
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')
  [ "$PART_START" ] || return 1
  # Return value will likely be error for fdisk as it fails to reload the
  # partition table because the root fs is mounted
  fdisk /dev/mmcblk0 <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF

cat <<EOF > /etc/rc.local &&
#!/bin/sh
echo "Expanding /dev/$ROOT_PART"
resize2fs /dev/$ROOT_PART
rm -f /etc/rc.local; cp -f /etc/rc.local.bak /etc/rc.local; /etc/rc.local

EOF
reboot
exit
}
raspi_config_expand() {
/usr/bin/env raspi-config --expand-rootfs
if [[ $? != 0 ]]; then
  return -1
else
  rm -f /etc/rc.local; cp -f /etc/rc.local.bak /etc/rc.local; /etc/rc.local
  reboot
  exit
fi
}
raspi_config_expand
echo "WARNING: Using backup expand..."
sleep 5
do_expand_rootfs
echo "ERROR: Expanding failed..."
sleep 5
rm -f /etc/rc.local; cp -f /etc/rc.local.bak /etc/rc.local; /etc/rc.local
exit 0
EOF1
    #####End no touch zone#####
    chmod +x "$mountdir/etc/rc.local"
  fi
  umount "$mountdir"
else
  echo "Skipping autoexpanding process..."
fi

#Make sure filesystem is ok
e2fsck -p -f "$loopback"
minsize=$(resize2fs -P "$loopback" | cut -d ':' -f 2 | tr -d ' ')
if [[ $currentsize -eq $minsize ]]; then
  echo "ERROR: Image already shrunk to smallest size"
  exit -6
fi

#Add some free space to the end of the filesystem
extra_space=$(($currentsize - $minsize))
for space in 5000 1000 100; do
  if [[ $extra_space -gt $space ]]; then
    minsize=$(($minsize + $space))
    break
  fi
done

#Shrink filesystem
resize2fs -p "$loopback" $minsize
if [[ $? != 0 ]]; then
  echo "ERROR: resize2fs failed..."
  mount "$loopback" "$mountdir"
  mv "$mountdir/etc/rc.local.bak" "$mountdir/etc/rc.local"
  umount "$mountdir"
  losetup -d "$loopback"
  exit -7
fi
sleep 1

#Shrink partition
partnewsize=$(($minsize * $blocksize))
newpartend=$(($partstart + $partnewsize))
parted -s -a minimal "$img" rm $partnum >/dev/null
parted -s "$img" unit B mkpart primary $partstart $newpartend >/dev/null

#Truncate the file
endresult=$(parted -ms "$img" unit B print free | tail -1 | cut -d ':' -f 2 | tr -d 'B')
truncate -s $endresult "$img"
aftersize=$(ls -lh "$img" | cut -d ' ' -f 5)

echo "Shrunk $img from $beforesize to $aftersize"
