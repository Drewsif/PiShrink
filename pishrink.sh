#!/bin/bash

version="v0.1.2"

CURRENT_DIR="$(pwd)"
SCRIPTNAME="${0##*/}"
MYNAME="${SCRIPTNAME%.*}"
LOGFILE="${CURRENT_DIR}/${SCRIPTNAME%.*}.log"
REQUIRED_TOOLS="parted losetup tune2fs md5sum e2fsck resize2fs"
ZIPTOOLS=("gzip xz")
declare -A ZIP_PARALLEL_TOOL=( [gzip]="pigz" [xz]="xz" ) # parallel zip tool to use in parallel mode
declare -A ZIP_PARALLEL_OPTIONS=( [gzip]="-f9" [xz]="-T0" ) # options for zip tools in parallel mode
declare -A ZIPEXTENSIONS=( [gzip]="gz" [xz]="xz" ) # extensions of zipped files

function k2m(){
	# Convert KBytes to MBytes and print it.
	printf "%'0.2f" $(bc<<<"scale=2;$1/1024")
}

function info() {
	echo "$1 ..."
}

function error() {
	local line=$1
	shift
	>&2 echo "ERROR (line $line):" $*
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
	exit 19

}

function make_expand_rootfs() {
	# Make pi expand root fs on next boot.
	local mountdir=$(mktemp -d)
	partprobe "$loopback"
	mount "$loopback" "$mountdir"

	if [ ! -d "$mountdir/etc" ]; then
		info "/etc not found, autoexpand will not be enabled"
		umount "$mountdir"
		return
	fi

	# Create a backup of rc.local if it's not marked.
	if [ -f "$mountdir/etc/rc.local" ]; then
		if [ "$(awk 'FNR==2{print $1}' $mountdir/etc/rc.local)" != '#DONOTBACKUP' ]; then
			info "Backing up original /etc/rc.local."
			mv "$mountdir/etc/rc.local" "$mountdir/etc/rc.local.bak"
		fi
	fi

	# Generate image's rc.local file to expand rootfs on first boot.
	info "Generating /etc/rc.local to expand rootfs on first boot."
	cat <<-RCLOCAL1 > "$mountdir/etc/rc.local"
	#!/bin/bash
	#DONOTBACKUP Prohibit pishrink.sh from creating backup to avoid boot looping.
	SIZE=$newsize
	
	RCLOCAL1

	cat <<-'RCLOCAL2' >> "$mountdir/etc/rc.local"
	do_expand_rootfs() {
		ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')

		if ! [[ "$ROOT_PART" =~ mmcblk.+ ]]; then
			echo "$ROOT_PART is not an SD card. Don't know how to expand"
			return 0
		fi

		PART_NUM=${ROOT_PART: -1}
		DEV=$(ls /dev/mmcblk[0-9])

		# Get the starting offset of the root partition
		PART_START=$(parted $DEV -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')
		[ "$PART_START" ] || return 1
		echo Root part $ROOT_PART, no. $PART_NUM, on $DEV, start $PART_START.
		if [ -n "$SIZE" ]; then
			echo Will resize root partition to $SIZE
			SIZE=+$SIZE
		else
			echo Will resize root partition to maximum available.
		fi
		# Return value will likely be error for fdisk as it fails to reload the
		# partition table because the root fs is mounted
		fdisk $DEV <<-EOFDISK
		p
		d
		$PART_NUM
		n
		p
		$PART_NUM
		$PART_START
		$SIZE
		p
		w
		EOFDISK

		cat <<-EOF > /etc/rc.local &&
		#!/bin/sh
		echo Expanding /dev/$ROOT_PART to ${SIZE:-maximum}
		resize2fs /dev/$ROOT_PART $SIZE
		rm -f /etc/rc.local
		cp -f /etc/rc.local.bak /etc/rc.local
		. /etc/rc.local
		
		EOF
		reboot
		exit
	}

	echo Expanding root...
	do_expand_rootfs
	echo ERROR: Expanding failed! Revert to original rc.local...
	if [ -f /etc/rc.local.bak ]; then
		cp -f /etc/rc.local.bak /etc/rc.local
		. /etc/rc.local
	fi
	exit 0
	RCLOCAL2

	chmod +x "$mountdir/etc/rc.local"
	umount "$mountdir"
}

print_usage() {
	cat <<-EOM
	Usage: $0 [-adhrspvzZ] file [newfile]
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
	EOM
	exit 0
}

newsize=
extraspace=100
noexpand=false
debug=false
repair=false
parallel=false
verbose=false
purge=false
ziptool=""

while getopts "e:adhl:nprvzZ" opt; do
  case "${opt}" in
    e) extraspace=$OPTARG;;
    a) parallel=true;;
    d) debug=true;;
    h) print_usage;;
    l) newsize=$OPTARG;;
    n) noexpand=true ;;
    p) purge=true;;
    r) repair=true;;
    v) verbose=true;;
    z) ziptool="gzip";;
    Z) ziptool="xz";;
    \?) error "Invalid option \"$OPTARG\""; exit 1 ;;
    :) error "ERROR: Option \"$OPTARG\" requires an argument."; exit 2 ;;
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
  print_usage
fi

if [[ ! -f "$img" ]]; then
  error $LINENO "$img is not a file..."
  exit 3
fi
if (( EUID != 0 )); then
  error $LINENO "You need to be running as root."
  exit 4
fi

# set locale to POSIX(English) temporarily
# these locale settings only affect the script and its sub processes

export LANGUAGE=POSIX
export LC_ALL=POSIX
export LANG=POSIX

# check selected compression tool is supported and installed
if [[ -n $ziptool ]]; then
	if [[ ! " ${ZIPTOOLS[@]} " =~ $ziptool ]]; then
		error $LINENO "$ziptool is an unsupported ziptool."
		exit 5
	else
		if [[ $parallel == true && $ziptool == "gzip" ]]; then
			REQUIRED_TOOLS="$REQUIRED_TOOLS pigz"
		else
			REQUIRED_TOOLS="$REQUIRED_TOOLS $ziptool"
		fi
	fi
fi

#Check that what we need is installed
for command in $REQUIRED_TOOLS; do
  command -v $command >/dev/null 2>&1
  if (( $? != 0 )); then
    error $LINENO "$command is not installed."
    exit 6
  fi
done

#Copy to new file if requested
if [ -n "$2" ]; then
  f="$2"
  if [[ -n $ziptool && "${f##*.}" == "${ZIPEXTENSIONS[$ziptool]}" ]]; then	# remove zip extension if zip requested because zip tool will complain about extension
    f="${f%.*}"
  fi
  info "Copying $1 to $f..."
  cp --reflink=auto --sparse=always "$1" "$f"
  if (( $? != 0 )); then
    error $LINENO "Could not copy file..."
    exit 7
  fi
  old_owner=$(stat -c %u:%g "$1")
  chown "$old_owner" "$f"
  img="$f"
fi

# cleanup at script exit
trap cleanup EXIT

#Gather info
info "Gathering data"
beforesize="$(ls -lh "$img" | cut -d ' ' -f 5)"
parted_output="$(parted -ms "$img" unit B print)"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	info "Possibly invalid image. Run 'parted $img unit B print' manually to investigate"
	exit 8
fi
partnum="$(echo "$parted_output" | tail -n 1 | cut -d ':' -f 1)"
partstart="$(echo "$parted_output" | tail -n 1 | cut -d ':' -f 2 | tr -d 'B')"
if [ -z "$(parted -s "$img" unit B print | grep "$partstart" | grep logical)" ]; then
    parttype="primary"
else
    parttype="logical"
fi
loopback="$(losetup -f --show -o "$partstart" "$img")"
# Wait 3 seconds to ensure loopback is ready.
sleep 3
tune2fs_output="$(tune2fs -l "$loopback")"
rc=$?
if (( $rc )); then
    echo "$tune2fs_output"
    error $LINENO "tune2fs failed. Unable to shrink this type of image"
    exit 9
fi

currentsize="$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)"
blocksize="$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)"

logVariables $LINENO beforesize parted_output partnum partstart parttype tune2fs_output currentsize blocksize

#Check if we should make pi expand rootfs on next boot
if [ "$parttype" == "logical" ]; then
  echo "WARNING: PiShrink does not yet support autoexpanding of this type of image"
elif [ "$noexpand" = false ]; then
  make_expand_rootfs
else
  echo "Skipping autoexpanding process..."
fi

if [[ $purge == true ]]; then
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"
	purge_dirs="/var/cache/apt/archives /var/log /var/tmp /tmp"
	total_purged=0
	for d in $purge_dirs; do
		let k=$(du -s ${mountdir}$d | awk '{print $1}')
		let total_purged+=$k
		info "Purging and save $(k2m $k) MBytes from $d"
		rm -fr ${mountdir}$d/* > /dev/null
	done
	info "Total $(k2m $total_purged) MBytes was purged."
  umount "$mountdir"
fi


#Make sure filesystem is ok
checkFilesystem

if ! minsize=$(resize2fs -P "$loopback"); then
	rc=$?
	error $LINENO "resize2fs failed with rc $rc"
	exit 10
fi
minsize=$(cut -d ':' -f 2 <<< "$minsize" | tr -d ' ')
logVariables $LINENO currentsize minsize
if [[ $currentsize -eq $minsize ]]; then
  error $LINENO "Image already shrunk to smallest size"
  exit 11
fi

#Add some free space to the end of the filesystem
targetsize=$(($minsize + $extraspace * 1024**2 / $blocksize))
if [ $targetsize -ge $currentsize ]; then
	info "Target size ($targetsize) too large, force to current size minus 1"
	let minsize=$currentsize-1
else
	minsize=$targetsize
fi
logVariables $LINENO targetsize currentsize minsize

#Shrink filesystem
info "Shrinking filesystem"
resize2fs -p "$loopback" $minsize
rc=$?
if (( $rc )); then
  error $LINENO "resize2fs failed with rc $rc"
  mount "$loopback" "$mountdir"
  mv "$mountdir/etc/rc.local.bak" "$mountdir/etc/rc.local"
  umount "$mountdir"
  losetup -d "$loopback"
  exit 12
fi
sleep 1

#Shrink partition
partnewsize=$(($minsize * $blocksize))
newpartend=$(($partstart + $partnewsize))
logVariables $LINENO partnewsize newpartend
parted -s -a minimal "$img" rm "$partnum"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit 13
fi

parted -s "$img" unit B mkpart "$parttype" "$partstart" "$newpartend"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit 14
fi

#Truncate the file
info "Shrinking image"
endresult=$(parted -ms "$img" unit B print free)
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit 15
fi

endresult=$(tail -1 <<< "$endresult" | cut -d ':' -f 2 | tr -d 'B')
logVariables $LINENO endresult
truncate -s "$endresult" "$img"
rc=$?
if (( $rc )); then
	error $LINENO "trunate failed with rc $rc"
	exit 16
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
			exit 17
		fi

	else # sequential
		info "Using $ziptool on the shrunk image"
		if ! $ziptool ${options} "$img"; then
			rc=$?
			error $LINENO "$ziptool failed with rc $rc"
			exit 18
		fi
	fi
	img=$img.${ZIPEXTENSIONS[$ziptool]}
fi

aftersize=$(ls -lh "$img" | cut -d ' ' -f 5)
logVariables $LINENO aftersize

info "Shrunk $img from $beforesize to $aftersize"
