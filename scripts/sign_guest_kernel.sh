#!/bin/bash
set -e
# calculate signatures over guest authenticated data, kernel image and device tree

SIGN_VERSION=0x0301

usage() {
	echo "usage:"
	echo "$0 -p <private_key -g <guest id>  -k <kernel> -d <dtb load address> \\"
	echo "-D <dtb file> -i <inittd load address> -I <inittŕd file> -c <guest certificate> \\"
	echo "-o <output name>"
	echo ""
	echo "  Create kernel image signature file"
}

add_hdr ()
{
	local MACIG
	local FLAGS
	local OFFSET
	local LOAD
	local SIZE
	local FILE=$5

	if [ -n "$FILE" ] ; then
		MACIG=$1
		FLAGS=$2
		OFFSET=$3
		LOAD=$4
		SIZE=$(stat -c"%s" "$FILE")
	else
		MACIG="\0\0\0\0"
		FLAGS=0
		OFFSET=0
		LOAD=0
		SIZE=0
	fi

	# magig
	echo -ne "$MACIG"
	# flags
	printf "0: %.8x" $(( "$FLAGS" )) | sed -E 's/0: (..)(..)(..)(..)/0:\4\3\2\1/' | xxd -r
	#size
	printf "0: %.8x" $(( $SIZE)) | \
		sed -E 's/0: (..)(..)(..)(..)/0:\4\3\2\1/' | xxd -r
	#offset
	printf "0: %.8x" $(( $OFFSET )) | \
		sed -E 's/0: (..)(..)(..)(..)/0:\4\3\2\1/' | xxd -r
	#load_address
	printf "0: %.16x" $(( $LOAD)) | \
		sed -E 's/0: (..)(..)(..)(..)(..)(..)(..)(..)/0:\8\7\6\5\4\3\2\1/'  | xxd -r

	if [ "$SIZE" -ne 0 ] ; then
		cat "$5" | openssl dgst -sha256 --binary
	else
		echo -n ""  | openssl dgst -sha256 --binary
	fi
}

add_dummy_hdr ()
{
	printf "0: %.8x" 0 | xxd -r
	printf "0: %.8x" 0 | xxd -r
	printf "0: %.16x" 0 | xxd -r
	printf "0: %.16x" 0 | xxd -r
	printf "0: %.16x" 0 | xxd -r 
	printf "0: %.16x" 0 | xxd -r
	printf "0: %.16x" 0 | xxd -r 
	printf "0: %.16x" 0 | xxd -r
	printf "0: %.8x" 0x644d5241 | 
		sed -E 's/0: (..)(..)(..)(..)/0:\4\3\2\1/' | xxd -r
	printf "0: %.8x" 0 | xxd -r
}

while getopts "h?p:g:k:d:D:i:I:o:c:" opt; do
	case "$opt" in
	h|\?)	-D "${DTB_FILE}" -d "$(DTB_ADDR)"

		usage
		exit 0
	;;
	p)  PRIV_KEY=$OPTARG
	;;
	g)  GUESTID=$OPTARG
	;;
	k)  KERNEL=$OPTARG
	;;
	d)  DTB_ADDR=$OPTARG
	;;
	D)  DTB_FILE=$OPTARG
	;;
	i)  INITRD_ADDR=$OPTARG
	;;
	I)  INITRD_FILE=$OPTARG
	;;
	c)  GUEST_CERT=$OPTARG
	;;
	o)  OUTFILE=$OPTARG
	;;
	esac
done

echo "$0 using:"
echo "key=$PRIV_KEY"
echo "guest_id=$GUESTID"
echo "guest cert"="$GUEST_CERT"
echo "kernel=$KERNEL"
echo "dtb file=$DTB_FILE"
echo "dtb load address=$DTB_ADDR"

echo ""

if [ -z "$PRIV_KEY" ] || [ -z "$KERNEL" ] || [ -z "$OUTFILE" ] ; then
    usage
    echo exit
    exit 1
fi
KERNEL_LEN=$(stat -c"%s" "$KERNEL")

if [ -z "$DTB_FILE" ]; then
	DTB_LEN=0
else
	DTB_LEN=$(stat -c"%s" "$DTB_FILE")
fi

DTB_OFFSET=$(( KERNEL_LEN  + 4096))
INIT_OFFSET=$(( DTB_OFFSET + DTB_LEN ))

# start to buils output image
#TMP_FILE=$(mktemp)
TMP_FILE=testfile
echo -n "SIGN" > "$TMP_FILE"
printf "0: %.8x" $(( "$SIGN_VERSION" )) | \
	sed -E 's/0: (..)(..)(..)(..)/0:\4\3\2\1/' | xxd -r >> "$TMP_FILE"

#add guest certificate

#define SIGNATURE_MAX_LEN 80
#define PUBKEY_MAX_LEN 80
#
#typedef struct {
#	uint32_t magic;
#	uint32_t size;
#	uint8_t key[PUBKEY_MAX_LEN];
#} public_key_t;
#
#typedef struct {
#	uint32_t magic;
#	uint32_t version;
#	public_key_t sign_key;
#	uint8_t signature[SIGNATURE_MAX_LEN];
#} guest_cert_t;
#
# CERT_MAX_LEN= sizof(guest_cert_t)
CERT_MAX_LEN=$((4 + 4 + 4 + 4 + 80 + 80))
dd if="$KERNEL" of="$OUTFILE" bs=64 count=1
#add_dummy_hdr > "$OUTFILE"
echo -n "SIGN" >> "$OUTFILE"
printf "0: %.8x" $(( "$SIGN_VERSION" )) | \
	sed -E 's/0: (..)(..)(..)(..)/0:\4\3\2\1/' | xxd -r >> "$OUTFILE"

cat "$GUEST_CERT" >> "$OUTFILE"
CERT_LEN=$(stat -c"%s" "$GUEST_CERT")

dd if=/dev/zero of="$OUTFILE" bs=$(("$CERT_MAX_LEN" - "$CERT_LEN" )) count=1 oflag=append \
	conv=notrunc status=none
if [ -n "$INITRD_FILE" ]; then
	echo "INITRD::$(stat -c"%s" "$INITRD_FILE")"
fi

#add loader data
add_hdr "KRNL" 0x00 0x1000 0 "$KERNEL" >> "$OUTFILE"
add_hdr "xxxx" 0 $DTB_OFFSET "$DTB_ADDR" "$DTB_FILE" >> "$OUTFILE"
#add_hdr "DEVT" 0x20 $DTB_OFFSET "$DTB_ADDR" "$DTB_FILE" >> "$OUTFILE"
##add_hdr "DEVT" 0x00 $DTB_OFFSET "$DTB_ADDR" "$DTB_FILE" >> "$OUTFILE"
add_hdr "INRD" 0x00 $INIT_OFFSET "$INITRD_ADDR" "$INITRD_FILE" >> "$OUTFILE"

# add guest id
echo -n "$GUESTID" >> "$OUTFILE"
dd if=/dev/zero of=$OUTFILE bs=$(( 16 - "${#GUESTID}" )) count=1 oflag=append \
	conv=notrunc status=none

# add signature
#echo -n "header hash:"
#cat  "${OUTFILE}" > tmpfile
#cat  "${OUTFILE}" | openssl dgst -sha256
cat  "${OUTFILE}" | openssl dgst -sha256 -sign "$PRIV_KEY" >> "$OUTFILE"

# add zeros so that size id 4096 bytes
LEN=$(stat -c"%s" "$OUTFILE")
PADS=$(( 4096 - LEN % 4096 ))
dd if=/dev/zero of="$OUTFILE" bs=$PADS count=1 oflag=append conv=notrunc \
	status=none
# Guest Authenticated data page is ready


cat "$KERNEL" >> "$OUTFILE"

if [ -n "$DTB_FILE" ]; then
	# add device three file if it is defined
	cat "$DTB_FILE" >>  "$OUTFILE"
fi
if [ -n "$INITRD_FILE" ]; then
	# add initrd file if is is defined
	cat "${INITRD_FILE}" >> "$OUTFILE"
fi

echo Signature file "$OUTFILE" is ready
#echo "TOTAL::$(stat -c"%s" "${OUTFILE}")"

exit 0
