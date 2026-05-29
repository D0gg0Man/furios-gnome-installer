# FuriOS GNOME Installer

Installs GNOME Shell alongside Phosh on FuriOS for Mali GPU devices (MT6877/Dimensity 900).

## Quick Install (pre-compiled binaries)
    git clone https://github.com/D0gg0man/furios-gnome-installer
    cd furios-gnome-installer
    sudo ./install.sh

## Build from source
If you want to build the components yourself instead of using the pre-compiled binaries:

    # 1. Clone all component repos
    git clone https://github.com/D0gg0man/furios-gnome-installer
    git clone https://github.com/D0gg0man/eglplatform-drmadapter
    git clone https://github.com/D0gg0man/libgbm-hybris
    git clone https://github.com/D0gg0man/drm-mali
    git clone https://github.com/D0gg0man/wayland-android-wlegl

    # 2. Build each component (requires libhybris-dev, android-headers)
    cd eglplatform-drmadapter && make && sudo make install && cd ..
    cd libgbm-hybris && make && sudo make install && cd ..
    cd drm-mali && make && sudo make install && cd ..
    cd wayland-android-wlegl && make && sudo make install && cd ..

    # 3. Run the installer (will use already-installed binaries)
    cd furios-gnome-installer
    sudo ./install.sh

Note: libEGL_libhybris.so.0.0.0 must be built from the patched libhybris fork:
    git clone https://github.com/D0gg0man/libhybris
    cd libhybris/hybris && ./autogen.sh && ./configure && make -C egl
    sudo cp egl/.libs/libEGL_libhybris.so.0.0.0 /path/to/furios-gnome-installer/

## What it installs
- GNOME Shell session with Mali GPU acceleration via HWC2
- Lock screen with PAM authentication
- Power key daemon for phone-like lock/sleep behaviour
- Brave browser WebGL acceleration support

## Requirements
- FuriOS on a Furiphone (Dimensity 900)
- phrog greeter
- libhybris with drmadapter patches found on my other repos

## Debug logging
Enable with: `G_MESSAGES_DEBUG=all`

## Components
- eglplatform_drmadapter.so - hybris EGL platform for HWC2
- gbm_hybris.so - GBM backend using hybris gralloc
- drm_shim.so - DRM ioctl interceptor for mutter KMS
- wlegl_server.so - android_wlegl injector for applications
- vulkan_x11_stub.so - Vulkan X11 stub for GTK4
- libEGL_libhybris.so.0.0.0 - patched libhybris EGL
