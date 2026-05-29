#!/bin/bash
# Build script for GNOME Mali components
# Outputs all binaries to ./built/
# Enable debug logging at runtime with: G_MESSAGES_DEBUG=all
set -e

SRCDIR="$(dirname "$(readlink -f "$0")")/src"
OUTDIR="$(dirname "$(readlink -f "$0")")/built"
mkdir -p "$OUTDIR"

GLIB_CFLAGS=$(pkg-config --cflags glib-2.0)
GLIB_LIBS=$(pkg-config --libs glib-2.0)
WAYLAND_CFLAGS=$(pkg-config --cflags wayland-server)
WAYLAND_LIBS=$(pkg-config --libs wayland-server)

echo "=== Building GNOME Mali components ==="

echo "[1/5] drm_shim.so — DRM ioctl interceptor for mutter KMS..."
gcc -shared -fPIC -O2 \
    -I/usr/include -I/usr/include/android -I/usr/include/libdrm \
    $GLIB_CFLAGS \
    -o "$OUTDIR/drm_shim.so" "$SRCDIR/drm_ioctl_shim.c" \
    -ldl -ldrm -lgralloc -lrt $GLIB_LIBS \
    -Wl,-soname,drm_shim.so

echo "[2/5] eglplatform_drmadapter.so — hybris EGL platform for HWC2..."
gcc -shared -fPIC -O2 \
    -I/usr/include -I/usr/include/android \
    $GLIB_CFLAGS \
    -o "$OUTDIR/eglplatform_drmadapter.so" "$SRCDIR/eglplatform_drmadapter.c" \
    -ldl -lhybris-common -lEGL $GLIB_LIBS \
    -Wl,-soname,eglplatform_drmadapter.so

echo "[3/5] gbm_hybris.so — GBM backend using hybris gralloc..."
gcc -shared -fPIC -O2 \
    -I/usr/include -I/usr/include/android \
    $GLIB_CFLAGS \
    -o "$OUTDIR/gbm_hybris.so" "$SRCDIR/gbm_hybris.c" \
    -ldl -lgralloc $GLIB_LIBS \
    -Wl,-soname,gbm_hybris.so

echo "[4/5] wlegl_server.so — android_wlegl injector for gnome-shell..."
gcc -shared -fPIC -O2 \
    $GLIB_CFLAGS $WAYLAND_CFLAGS \
    -o "$OUTDIR/wlegl_server.so" "$SRCDIR/wlegl_server.c" \
    -ldl $GLIB_LIBS $WAYLAND_LIBS \
    -Wl,-soname,wlegl_server.so

echo "[5/5] vulkan_x11_stub.so — Vulkan X11 stub for GTK4 apps..."
gcc -shared -fPIC -O2 -static-libgcc \
    -o "$OUTDIR/vulkan_x11_stub.so" "$SRCDIR/vulkan_x11_stub.c" \
    -Wl,-soname,vulkan_x11_stub.so

echo ""
echo "=== All components built in $OUTDIR ==="
echo ""
echo "NOTE: libEGL_libhybris.so.0.0.0 must be built separately from the"
echo "      patched libhybris source in libhybris-src/:"
echo "      cd libhybris-src/hybris && make -C egl"
echo "      cp egl/.libs/libEGL_libhybris.so.0.0.0 ../../built/"

# Copy libEGL_libhybris if already built from libhybris-src
if [ -f "$(dirname "$0")/libhybris-src/hybris/egl/.libs/libEGL_libhybris.so.0.0.0" ]; then
    echo "Copying patched libEGL_libhybris..."
    cp "$(dirname "$0")/libhybris-src/hybris/egl/.libs/libEGL_libhybris.so.0.0.0" "$OUTDIR/"
    echo "libEGL_libhybris.so.0.0.0 copied to $OUTDIR"
else
    echo "NOTE: libEGL_libhybris.so.0.0.0 not found - build it first:"
    echo "  cd libhybris-src/hybris && make -C egl"
fi

# Copy non-compiled files to built/
echo "Copying supporting files to $OUTDIR..."
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cp "$SCRIPT_DIR/gnome-mali-lock-extension.js" "$OUTDIR/"
cp "$SCRIPT_DIR/gnome-mali-lock-metadata.json" "$OUTDIR/"
cp "$SCRIPT_DIR/gnome-mali-power-daemon" "$OUTDIR/"
cp "$SCRIPT_DIR/gnome-mali-power-key" "$OUTDIR/"
echo "Done."
