# FuriOS GNOME Installer

Installs GNOME Shell alongside Phosh on FuriOS for Mali GPU devices (MT6877/Dimensity 900).

## Quick Install
    git clone https://github.com/D0gg0man/furios-gnome-installer
    cd furios-gnome-installer
    sudo ./install.sh

## What it installs
- GNOME Shell session with Mali GPU acceleration via HWC2
- Lock screen with PAM authentication
- Power key daemon for phone-like lock/sleep behaviour
- Brave browser WebGL acceleration support

## Requirements
- FuriOS on MT6877 (Dimensity 900)
- phrog greeter
- libhybris with drmadapter patches

## Debug logging
Enable with: `G_MESSAGES_DEBUG=all`

## Components
- eglplatform_drmadapter.so - hybris EGL platform for HWC2
- gbm_hybris.so - GBM backend using hybris gralloc
- drm_shim.so - DRM ioctl interceptor for mutter KMS
- wlegl_server.so - android_wlegl injector for Andromeda
- vulkan_x11_stub.so - Vulkan X11 stub for GTK4
- libEGL_libhybris.so.0.0.0 - patched libhybris EGL
