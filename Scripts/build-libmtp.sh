#!/bin/sh
set -eu
# Installs only into an explicit development prefix, never into a system directory.
: "${KINDLE_MARGIN_MTP_PREFIX:?Set an absolute local install prefix}"
: "${KINDLE_MARGIN_LIBUSB_PREFIX:?Set the installed libusb prefix}"
case "$KINDLE_MARGIN_MTP_PREFIX" in /*) ;; *) echo 'MTP prefix must be absolute' >&2; exit 1;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/kindle-margin-mtp.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
curl --fail --location --proto '=https' --proto-redir '=https' --max-time 120 \
  https://downloads.sourceforge.net/project/libmtp/libmtp/1.1.22/libmtp-1.1.22.tar.gz -o "$work/libmtp.tar.gz"
expected=c3fcf411aea9cb9643590cbc9df99fa5fe30adcac695024442973d76fa5f87bc
actual=$(shasum -a 256 "$work/libmtp.tar.gz" | cut -d ' ' -f 1)
[ "$actual" = "$expected" ] || { echo 'libmtp archive hash mismatch' >&2; exit 1; }
tar -xzf "$work/libmtp.tar.gz" -C "$work"
cd "$work/libmtp-1.1.22"
./configure --prefix="$KINDLE_MARGIN_MTP_PREFIX" --disable-static --enable-shared --disable-mtpz --disable-doxygen \
  LIBUSB_CFLAGS="-I$KINDLE_MARGIN_LIBUSB_PREFIX/include/libusb-1.0" \
  LIBUSB_LIBS="-L$KINDLE_MARGIN_LIBUSB_PREFIX/lib -lusb-1.0"
make -j2
make install
mkdir -p "$KINDLE_MARGIN_MTP_PREFIX/share/licenses/libmtp"
cp COPYING "$KINDLE_MARGIN_MTP_PREFIX/share/licenses/libmtp/COPYING"
