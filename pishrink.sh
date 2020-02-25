#!/bin/bash

version="v0.1.3"

CURRENT_DIR=$(pwd)
SCRIPTNAME="${0##*/}"
LOGFILE=${CURRENT_DIR}/${SCRIPTNAME%.*}.log

function info() {
	echo "$SCRIPTNAME: $1..."
}

function error() {
	echo -n "$SCRIPTNAME: ERROR occured in line $1: "
	shift
	echo "$@"
}

function cleanup() {
	if losetup "$loopback" &>/dev/null; then
		losetup -d "$loopback"
	fi
	if [ "$debug" = true ]; then
		local old_owner=$(stat -c %u:%g "$src")
		chown "$old_owner" "$LOGFILE"
	fi

}

function logVariables() {
	if [ "$debug" = true ]; then
		echo "Line $1" >> "$LOGFILE"
		shift
		local v var
		for var in "$@"; do
			eval "v=\$$var"
			echo "$var: $v" >> "$LOGFILE"
		done
	fi
}

function checkFilesystem() {
	info "Checking filesystem"
	e2fsck -pf "$loopback"
	(( $? < 4 )) && return

	info "Filesystem error detected!"

	info "Trying to recover corrupted filesystem"
	e2fsck -y "$loopback"
	(( $? < 4 )) && return

if [[ $repair == true ]]; then
	info "Trying to recover corrupted filesystem - Phase 2"
	e2fsck -fy -b 32768 "$loopback"
	(( $? < 4 )) && return
fi
	error $LINENO "Filesystem recoveries failed. Giving up..."
	exit -9

}

help() {
	local help
	read -r -d '' help << EOM
Usage: $0 [-sdrpzh] imagefile.img [newimagefile.img]

  -s: Don't expand filesystem when image is booted the first time
  -d: Write debug messages in a debug log file
  -r: Use advanced filesystem repair option if the normal one fails
  -p: Remove logs, apt archives, dhcp leases and ssh hostkeys
  -z: Gzip compress image after shrinking
EOM
	echo "$help"
	exit -1
}

usage() {
	echo "Usage: $0 [-sdrpzh] imagefile.img [newimagefile.img]"
	echo ""
	echo "  -s: Skip autoexpand"
	echo "  -d: Debug mode on"
	echo "  -r: Use advanced repair options"
	echo "  -p: Remove logs, apt archives, dhcp leases and ssh hostkeys"
	echo "  -z: Gzip compress image after shrinking"
	echo "  -h: display help text"
	exit -1
}

should_skip_autoexpand=false
debug=false
repair=false
gzip_compress=false
prep=false

while getopts ":sdrpzh" opt; do
  case "${opt}" in
    s) should_skip_autoexpand=true ;;
    d) debug=true;;
    r) repair=true;;
    p) prep=true;;
    z) gzip_compress=true;;
    h) help;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

if [ "$debug" = true ]; then
	info "Creating log file $LOGFILE"
	rm "$LOGFILE" &>/dev/null
	exec 1> >(stdbuf -i0 -o0 -e0 tee -a "$LOGFILE" >&1)
	exec 2> >(stdbuf -i0 -o0 -e0 tee -a "$LOGFILE" >&2)
fi

echo "${0##*/} $version"

#Args
src="$1"
img="$1"

#Usage checks
if [[ -z "$img" ]]; then
  usage
fi
if [[ ! -f "$img" ]]; then
  error $LINENO "$img is not a file..."
  exit -2
fi
if (( EUID != 0 )); then
  error $LINENO "You need to be running as root."
  exit -3
fi

#Check that what we need is installed
for command in parted losetup tune2fs md5sum e2fsck resize2fs; do
  command -v $command >/dev/null 2>&1
  if (( $? != 0 )); then
    error $LINENO "$command is not installed."
    exit -4
  fi
done

#Copy to new file if requested
if [ -n "$2" ]; then
  info "Copying $1 to $2..."
  cp --reflink=auto --sparse=always "$1" "$2"
  if (( $? != 0 )); then
    error $LINENO "Could not copy file..."
    exit -5
  fi
  old_owner=$(stat -c %u:%g "$1")
  chown "$old_owner" "$2"
  img="$2"
fi

# cleanup at script exit
trap cleanup ERR EXIT

#Gather info
info "Gathering data"
beforesize=$(ls -lh "$img" | cut -d ' ' -f 5)
parted_output=$(parted -ms "$img" unit B print | tail -n 1)
partnum=$(echo "$parted_output" | cut -d ':' -f 1)
partstart=$(echo "$parted_output" | cut -d ':' -f 2 | tr -d 'B')
loopback=$(losetup -f --show -o "$partstart" "$img")
tune2fs_output=$(tune2fs -l "$loopback")
currentsize=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
blocksize=$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)

logVariables $LINENO tune2fs_output currentsize blocksize

#Check if we should make pi expand rootfs on next boot
if [ "$should_skip_autoexpand" = false ]; then
  #Make pi expand rootfs on next boot
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"
  #From https://raw.githubusercontent.com/RPi-Distro/pi-gen/master/stage2/01-sys-tweaks/files/resize2fs_once
  cat <<\EOF > "$mountdir/etc/init.d/resize2fs_once"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 3
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO
. /lib/lsb/init-functions
case "$1" in
  start)
    log_daemon_msg "Starting resize2fs_once"
    ROOT_DEV=$(findmnt / -o source -n) &&
    resize2fs $ROOT_DEV &&
    update-rc.d resize2fs_once remove &&
    rm /etc/init.d/resize2fs_once &&
    log_end_msg $?
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF
  chmod +x "$mountdir/etc/init.d/resize2fs_once"
  ln -s "$mountdir/etc/init.d/resize2fs_once" "$mountdir/etc/rc3.d/resize2fs_once"
  umount "$mountdir"
else
  echo "Skipping autoexpanding process..."
fi

if [[ $prep == true ]]; then
  info "Syspreping: Removing logs, apt archives, dhcp leases and ssh hostkeys"
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"
  rm -rf "$mountdir/var/cache/apt/archives/*" "$mountdir/var/lib/dhcpcd5/*" "$mountdir/var/log/*" "$mountdir/var/tmp/*" "$mountdir/tmp/*" "$mountdir/etc/ssh/*_host_*" 
  umount "$mountdir"
fi


#Make sure filesystem is ok
checkFilesystem

if ! minsize=$(resize2fs -P "$loopback"); then
	rc=$?
	error $LINENO "resize2fs failed with rc $rc"
	exit -10
fi
minsize=$(cut -d ':' -f 2 <<< "$minsize" | tr -d ' ')
logVariables $LINENO minsize
if [[ $currentsize -eq $minsize ]]; then
  error $LINENO "Image already shrunk to smallest size"
  exit -11
fi

#Add some free space to the end of the filesystem
extra_space=$(($currentsize - $minsize))
logVariables $LINENO extra_space
for space in 5000 1000 100; do
  if [[ $extra_space -gt $space ]]; then
    minsize=$(($minsize + $space))
    break
  fi
done
logVariables $LINENO minsize

#Shrink filesystem
info "Shrinking filesystem"
resize2fs -p "$loopback" $minsize
if [[ $? != 0 ]]; then
  error $LINENO "resize2fs failed"
  mount "$loopback" "$mountdir"
  mv "$mountdir/etc/rc.local.bak" "$mountdir/etc/rc.local"
  umount "$mountdir"
  losetup -d "$loopback"
  exit -12
fi
sleep 1

#Shrink partition
partnewsize=$(($minsize * $blocksize))
newpartend=$(($partstart + $partnewsize))
logVariables $LINENO partnewsize newpartend
if ! parted -s -a minimal "$img" rm "$partnum"; then
	rc=$?
	error $LINENO "parted failed with rc $rc"
	exit -13
fi

if ! parted -s "$img" unit B mkpart primary "$partstart" "$newpartend"; then
	rc=$?
	error $LINENO "parted failed with rc $rc"
	exit -14
fi

#Truncate the file
info "Shrinking image"
if ! endresult=$(parted -ms "$img" unit B print free); then
	rc=$?
	error $LINENO "parted failed with rc $rc"
	exit -15
fi

endresult=$(tail -1 <<< "$endresult" | cut -d ':' -f 2 | tr -d 'B')
logVariables $LINENO endresult
if ! truncate -s "$endresult" "$img"; then
	rc=$?
	error $LINENO "trunate failed with rc $rc"
	exit -16
fi

if [[ $gzip_compress == true ]]; then
    info "Gzipping the shrunk image"
    if [[ ! $(gzip -f9 "$img") ]]; then
        img=$img.gz
    fi
fi

aftersize=$(ls -lh "$img" | cut -d ' ' -f 5)
logVariables $LINENO aftersize

info "Shrunk $img from $beforesize to $aftersize"
