#!/bin/bash

version="v0.1.3"

CURRENT_DIR="$(pwd)"
SCRIPTNAME="${0##*/}"
MYNAME="${SCRIPTNAME%.*}"
LOGFILE="${CURRENT_DIR}/${SCRIPTNAME%.*}.log"
REQUIRED_TOOLS="parted losetup tune2fs md5sum e2fsck resize2fs"
ZIPTOOLS=("gzip xz")
declare -A ZIP_PARALLEL_TOOL=( [gzip]="pigz" [xz]="xz" ) # parallel zip tool to use in parallel mode
declare -A ZIP_PARALLEL_OPTIONS=( [gzip]="-f9" [xz]="-T0" ) # options for zip tools in parallel mode
declare -A ZIPEXTENSIONS=( [gzip]="gz" [xz]="xz" ) # extensions of zipped files

function info() {
	echo "$SCRIPTNAME: $1 ..."
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
Usage: $0 [-adfhrspvzZ] imagefile.img [newimagefile.img]

  -a         Compress image in parallel using multiple cores
  -d         Write debug messages in a debug log file
  -f			 Force skip of partition checks for NOOBS and PINN
  -h			 Help
  -p         Remove logs, apt archives, dhcp leases and ssh hostkeys
  -r         Use advanced filesystem repair option if the normal one fails
  -s         Don't expand filesystem when image is booted the first time
  -v			 Be verbose
  -z         Compress image after shrinking with gzip
  -Z         Compress image after shrinking with xz
EOM
	echo "$help"
	exit -1
}

should_skip_autoexpand=false
debug=false
repair=false
parallel=false
verbose=false
prep=false
ziptool=""
required_tools="$REQUIRED_TOOLS"
skipPartitionChecks=false

while getopts ":adfhprsvzZ" opt; do
  case "${opt}" in
    a) parallel=true;;
    d) debug=true;;
    f) skipPartitionChecks=true;;
    h) help;;
    p) prep=true;;
    r) repair=true;;
    s) should_skip_autoexpand=true ;;
    v) verbose=true;;
    z) ziptool="gzip";;
    Z) ziptool="xz";;
    *) help;;
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
  help
  exit 42
fi

if [[ ! -f "$img" ]]; then
  error $LINENO "$img is not a file..."
  exit -2
fi
if (( EUID != 0 )); then
  error $LINENO "You need to be running as root."
  exit -3
fi

# check selected compression tool is supported and installed
if [[ -n $ziptool ]]; then
	if [[ ! " ${ZIPTOOLS[@]} " =~ " $ziptool " ]]; then
		error $LINENO "$ziptool is an unsupported ziptool."
		exit -17
	else
		if [[ $parallel == true && ziptool == "gzip" ]]; then
			REQUIRED_TOOLS="$REQUIRED_TOOLS pigz"
		else
			REQUIRED_TOOLS="$REQUIRED_TOOLS $ziptool"
		fi
	fi
fi

if [[ $skipPartitionChecks == false ]]; then
	#Check we have a Raspbian image, NOOBS, PINN et al is not supported
	numPartitions=$(fdisk -l $img | grep "^Device" -A 10 | grep -v "^Device" | wc -l)
	rc=$?
	if (( $rc )); then
		error $LINENO "fdisk error. rc: $rc"
		exit 42
	fi 
	if (( $numPartitions != 2 )); then
	  error $LINENO "$img has $numPartitions partitions. Note: NOOBS or PINN images are not supported."
	  exit 42
	fi
	if fdisk -l $img | grep -iq extended; then
	  error $LINENO "$img has an extended partition. Note: NOOBS or PINN images are not supported."
	  exit 42
	fi
fi

#Check that what we need is installed
for command in $REQUIRED_TOOLS; do
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
beforesize="$(ls -lh "$img" | cut -d ' ' -f 5)"
parted_output="$(parted -ms "$img" unit B print)"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	info "Possibly invalid image. Run 'parted $img unit B print' manually to investigate"
	exit -6
fi

partnum="$(echo "$parted_output" | tail -n 1 | cut -d ':' -f 1)"
partstart="$(echo "$parted_output" | tail -n 1 | cut -d ':' -f 2 | tr -d 'B')"
loopback="$(losetup -f --show -o "$partstart" "$img")"
rc=$?
if (( $rc )); then
	error $LINENO "losetup failed with rc $rc"
	exit 42
fi
tune2fs_output="$(tune2fs -l "$loopback")"
currentsize="$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)"
blocksize="$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)"

logVariables $LINENO beforesize parted_output partnum partstart tune2fs_output currentsize blocksize

#Check if we should make pi expand rootfs on next boot
if [ "$should_skip_autoexpand" = false ]; then
  #Make pi expand rootfs on next boot
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"
  rc=$?
  if (( $rc )); then
	error $LINENO "mount failed with rc $rc"
	exit 42
  fi

  if [[ ! -f "$mountdir/etc/rc.local" ]]; then
	error $LINENO "/etc/rc.local not found in $img"
   exit 42
  fi

  if [ "$(md5sum "$mountdir/etc/rc.local" | cut -d ' ' -f 1)" != "0542054e9ff2d2e0507ea1ffe7d4fc87" ]; then
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

if [[ $prep == true ]]; then
  info "Syspreping: Removing logs, apt archives, dhcp leases and ssh hostkeys"
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"
  rm -rf "$mountdir/var/cache/apt/archives/*" "$mountdir/var/lib/dhcpcd5/*" "$mountdir/var/log/*" "$mountdir/var/tmp/*" "$mountdir/tmp/*" "$mountdir/etc/ssh/*_host_*"
  umount "$mountdir"
fi


#Make sure filesystem is ok
checkFilesystem

minsize=$(resize2fs -P "$loopback"); rc=$?
if (( $rc )); then
	error $LINENO "resize2fs failed with rc $rc"
	exit -10
fi
minsize=$(cut -d ':' -f 2 <<< "$minsize" | tr -d ' ')
logVariables $LINENO currentsize minsize
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
parted -s -a minimal "$img" rm "$partnum"; rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit -13
fi

parted -s "$img" unit B mkpart primary "$partstart" "$newpartend"; rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit -14
fi

#Truncate the file
info "Shrinking image"
endresult=$(parted -ms "$img" unit B print free); rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit -15
fi

endresult=$(tail -1 <<< "$endresult" | cut -d ':' -f 2 | tr -d 'B')
logVariables $LINENO endresult
truncate -s "$endresult" "$img"; rc=$?
if (( $rc )); then
	error $LINENO "trunate failed with rc $rc"
	exit -16
fi

# handle compression
if [[ -n $ziptool ]]; then
	options=""
	envVarname="${MYNAME^^}_${ziptool^^}" # PISHRINK_GZIP or PISHRINK_XZ environment variables allow to override all options for gzip or xz
	[[ $parallel == true ]] && options="${ZIP_PARALLEL_OPTIONS[$ziptool]}"
	[[ -v $envVarname ]] && options="${!envVarname}" # if environment variable defined use these options
	[[ $verbose == true ]] && options="$options -v" # add verbose flag if requested
	
	if [[ $parallel == true ]]; then
		parallel_tool="${ZIP_PARALLEL_TOOL[$ziptool]}"
		info "Using $parallel_tool on the shrunk image"
		if ! $parallel_tool ${options} "$img"; then
			rc=$?
			error $LINENO "$parallel_tool failed with rc $rc"
			exit -18
		fi
		
	else # sequential
		info "Using $ziptool on the shrunk image"
		if ! $ziptool ${options} $img; then
			rc=$?
			error $LINENO "$ziptool failed with rc $rc"
			exit -19
		fi
	fi
	img=$img.${ZIPEXTENSIONS[$ziptool]}
fi

aftersize=$(ls -lh "$img" | cut -d ' ' -f 5)
logVariables $LINENO aftersize

info "Shrunk $img from $beforesize to $aftersize"
