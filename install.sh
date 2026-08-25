#!/bin/bash
# =============================================================================
# GNOME Mali Session Installer for FuriOS (MT6877 / Dimensity 900)
# Installs GNOME Shell alongside Phosh via the phrog greeter
#
# Usage: sudo ./install-gnome-mali.sh
#
# Required files (same directory as this script):
#   libEGL_libhybris.so.0.0.0   — patched libhybris EGL (GBM→drmadapter routing)
#   eglplatform_drmadapter.so   — hybris EGL platform (HWC2 init + present)
#   drm_shim.so                 — DRM ioctl interceptor for mutter KMS
#   wlegl_server.so             — Wayland EGL server
#   vulkan_x11_stub.so          — stub for missing X11 Vulkan symbols in GTK4
# =============================================================================

set -e

INSTALL_DIR="$(dirname "$(readlink -f "$0")")/built"
EGL_LIB_DIR="/usr/lib/aarch64-linux-gnu"
HYBRIS_PLATFORM_DIR="/usr/lib/aarch64-linux-gnu/libhybris"
BACKUP_DIR="/var/lib/gnome-mali/backups"
STATE_FILE="/var/lib/gnome-mali/installed"

echo "=== GNOME Mali Session Installer ==="
echo "Install source: $INSTALL_DIR"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo $0)"
    exit 1
fi

# -----------------------------------------------------------------------------
# Verify required files
# -----------------------------------------------------------------------------
REQUIRED=(
    libEGL_libhybris.so.0.0.0
    eglplatform_drmadapter.so
    eglplatform_drmadapter_client.so
    libdrm-hybris.so
    rendernode-shim.so
    xifevent-shim.so
    wlegl_server.so
    vulkan_x11_stub.so
    gnome-mali-session
    brave-gpu
    Xwayland-wrapper
    brave-browser-stable-wrapper
    gnome-mali-lock-extension.js
    gnome-mali-lock-metadata.json
    gnome-mali-power-daemon
    gnome-mali-power-key
)

for f in "${REQUIRED[@]}"; do
    if [ ! -f "$INSTALL_DIR/$f" ]; then
        echo "ERROR: Missing required file: $INSTALL_DIR/$f"
        exit 1
    fi
done

# -----------------------------------------------------------------------------
# Backup helper — only backs up once (won't overwrite existing backup)
# -----------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"

backup() {
    local src="$1"
    local dest="$BACKUP_DIR/$(echo "$src" | tr '/' '_')"
    if [ -f "$src" ] && [ ! -f "$dest" ]; then
        cp -a "$src" "$dest"
        echo "  backed up: $src -> $dest"
    fi
}

# -----------------------------------------------------------------------------
# Step 1 — Patched libhybris EGL
# Adds EGL_PLATFORM_GBM_KHR routing to drmadapter platform,
# and GBM pixel format fix in eglGetConfigAttrib.
# -----------------------------------------------------------------------------
echo "[1/7] Installing patched libhybris EGL..."
backup "$EGL_LIB_DIR/libEGL_libhybris.so.0.0.0"

cp "$INSTALL_DIR/libEGL_libhybris.so.0.0.0" /tmp/_libhybris_egl.so
mv /tmp/_libhybris_egl.so "$EGL_LIB_DIR/libEGL_libhybris.so.0.0.0"
chown root:root "$EGL_LIB_DIR/libEGL_libhybris.so.0.0.0"
chmod 755 "$EGL_LIB_DIR/libEGL_libhybris.so.0.0.0"
ldconfig

# -----------------------------------------------------------------------------
# Step 2 — drmadapter hybris EGL platform + shim libraries
# -----------------------------------------------------------------------------
echo "[2/8] Installing drmadapter platform and shim libraries..."
backup /usr/lib/aarch64-linux-gnu/libdrm-hybris.so
backup /usr/local/lib/wlegl_server.so
backup /usr/local/lib/vulkan_x11_stub.so
backup /usr/local/lib/rendernode-shim.so
backup /usr/local/lib/xifevent-shim.so

mkdir -p "$HYBRIS_PLATFORM_DIR"
install -m 755 -o root -g root "$INSTALL_DIR/eglplatform_drmadapter.so" \
    "$HYBRIS_PLATFORM_DIR/eglplatform_drmadapter.so"

# Client-mode drmadapter. HWC2 allows one composer client per system and the
# compositor holds it, so any other process that loads the normal platform
# aborts in libhwc2_compat_layer ("failed to create composer client"). This
# build skips HWC2 init when it is not the compositor. It is installed
# separately and selected per-process with HYBRIS_EGLPLATFORM_DIR, leaving the
# compositor's own copy untouched.
install -d -m 755 /usr/local/lib/drmadapter-client
install -m 755 "$INSTALL_DIR/eglplatform_drmadapter_client.so" \
    /usr/local/lib/drmadapter-client/eglplatform_drmadapter.so

# libdrm-hybris replaces the older drm_shim.so: same job, but it also carries
# the panel-power path, the synthetic page-flip completions and the KWin/phoc
# compatibility paths.
install -m 755 "$INSTALL_DIR/libdrm-hybris.so" /usr/lib/aarch64-linux-gnu/libdrm-hybris.so
install -m 755 "$INSTALL_DIR/wlegl_server.so"    /usr/local/lib/wlegl_server.so
install -m 755 "$INSTALL_DIR/vulkan_x11_stub.so" /usr/local/lib/vulkan_x11_stub.so
install -m 755 "$INSTALL_DIR/rendernode-shim.so" /usr/local/lib/rendernode-shim.so
install -m 755 "$INSTALL_DIR/xifevent-shim.so"   /usr/local/lib/xifevent-shim.so

# Retire the superseded shim so both cannot be preloaded at once.
rm -f /usr/local/lib/drm_shim.so

# Step 3 — /etc/ld.so.preload
# libdrm-hybris must be system-wide: it stands in for libseat as well, and its
# interception is inert outside a compositor (it checks /proc/self/exe).
# Everything else is session-only, loaded from the session wrapper, to avoid
# injecting hybris into Chromium GPU sandboxes that cannot reach the hybris
# linker. vulkan_x11_stub.so is installed but not preloaded -- the working
# device does not need it in ld.so.preload.
# -----------------------------------------------------------------------------
echo "[3/8] Configuring ld.so.preload..."
backup /etc/ld.so.preload

touch /etc/ld.so.preload
sed -i '\|/usr/local/lib/drm_shim.so|d'     /etc/ld.so.preload
sed -i '\|/usr/local/lib/wlegl_server.so|d' /etc/ld.so.preload
grep -qxF '/usr/lib/aarch64-linux-gnu/libdrm-hybris.so' /etc/ld.so.preload || \
    echo '/usr/lib/aarch64-linux-gnu/libdrm-hybris.so' >> /etc/ld.so.preload

# Step 4 — Session wrapper
# No vendor swap needed — libhybris routes GBM to drmadapter natively
# -----------------------------------------------------------------------------
echo "[4/8] Installing session wrapper..."
backup /usr/libexec/gnome-mali-session

# Shipped as a file rather than a heredoc: this is the exact script running on a
# working device, so the two cannot drift.
install -m 755 "$INSTALL_DIR/gnome-mali-session" /usr/libexec/gnome-mali-session

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Step 4b — Xwayland and Brave wrappers
#
# Xwayland: it initialises hybris EGL, which routes to drmadapter, which tries
# to take the single HWC2 composer client the compositor already holds --
# libhwc2_compat_layer does not fail gracefully, it aborts. Xwayland then dies
# the moment any X11 client appears, and mutter, focusing a Wayland window with
# timestamp 0, does an X11 round-trip that never returns and spins at 100% until
# the session is killed. Pointing Xwayland at the client-mode drmadapter avoids
# the abort; xifevent-shim in the session wrapper bounds the round-trip so a
# dead X server cannot hang the compositor either way.
#
# Brave: Chromium needs a DRM render node, which this hardware has none of.
# Optional -- skipped when Brave is not installed.
# -----------------------------------------------------------------------------
echo "[4b/8] Installing Xwayland and browser wrappers..."

if [ -f /usr/bin/Xwayland ] && [ ! -f /usr/bin/Xwayland.real ]; then
    backup /usr/bin/Xwayland
    mv /usr/bin/Xwayland /usr/bin/Xwayland.real
    install -m 755 "$INSTALL_DIR/Xwayland-wrapper" /usr/bin/Xwayland
    echo "  Xwayland wrapped (original at /usr/bin/Xwayland.real)"
fi

if [ -e /usr/bin/brave-browser-stable ]; then
    backup /usr/bin/brave-browser-stable
    install -m 755 "$INSTALL_DIR/brave-gpu" /usr/local/bin/brave-gpu
    install -m 755 "$INSTALL_DIR/brave-browser-stable-wrapper" /usr/bin/brave-browser-stable
    echo "  Brave wrapped for GPU acceleration"
    echo "  NOTE: a brave-browser package update restores the original launcher;"
    echo "        re-run this installer if brave://gpu goes back to software."
fi

# Step 5 — Wayland session desktop entry
# -----------------------------------------------------------------------------
echo "[5/8] Installing wayland session entry..."
backup /usr/share/wayland-sessions/gnome-mali.desktop

cat > /usr/share/wayland-sessions/gnome-mali.desktop << 'EOF'
[Desktop Entry]
Name=GNOME Mali
Comment=GNOME Shell on Mali GPU via HWC2
Exec=/usr/libexec/gnome-mali-session
TryExec=/usr/libexec/gnome-mali-session
Type=Application
DesktopNames=GNOME
X-GDM-SessionRegisters=true
EOF

# -----------------------------------------------------------------------------
# Step 6 — greetd config
# No vendor wrapper needed for phrog — libhybris patch is transparent to phosh
# -----------------------------------------------------------------------------
echo "[6/8] Configuring greetd..."
backup /etc/greetd/phrog.toml

cat > /etc/greetd/phrog.toml << 'EOF'
[terminal]
vt = 7

[default_session]
command = "/usr/libexec/phrog-greetd-session-wrapper"
user = "_greetd"
EOF

# -----------------------------------------------------------------------------
# Step 7 — systemd boot service
# Ensures clean state on boot (no-op now, kept for safety)
# -----------------------------------------------------------------------------
echo "[7/8] Installing systemd boot service and session units..."

cat > /etc/systemd/system/gnome-mali-boot.service << 'EOF'
[Unit]
Description=GNOME Mali boot initialisation
Before=greetd.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Remove custom wayland target override that blocked gnome-shell startup
rm -f /usr/lib/systemd/user/gnome-session-wayland@gnome-mali.target

# Pull gnome-session-basic-services into the gnome-mali session only.
# This starts org.gnome.Shell.target, gsd-power, gsd-media-keys, etc.
# Using gnome-session@gnome-mali.target.wants so phrog is not affected.
mkdir -p /usr/lib/systemd/user/gnome-session@gnome-mali.target.wants/
ln -sf /usr/lib/systemd/user/gnome-session-basic-services.target \
    /usr/lib/systemd/user/gnome-session@gnome-mali.target.wants/gnome-session-basic-services.target

systemctl daemon-reload
systemctl enable gnome-mali-boot.service

# -----------------------------------------------------------------------------
# Step 8 — Lock screen extension + power key daemon
# -----------------------------------------------------------------------------
echo "[8/8] Installing lock screen..."

# PAM auth helper (setuid root for shadow auth)
cat > /tmp/_pamhelper.c << 'CSRC'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <security/pam_appl.h>
static const char *_pw;
static int conv(int n, const struct pam_message **msg, struct pam_response **resp, void *d) {
    *resp = calloc(n, sizeof(struct pam_response));
    for (int i=0;i<n;i++)
        if (msg[i]->msg_style==PAM_PROMPT_ECHO_OFF||msg[i]->msg_style==PAM_PROMPT_ECHO_ON)
            (*resp)[i].resp=strdup(_pw);
    return PAM_SUCCESS;
}
int main(int argc,char*argv[]) {
    if(argc!=3){return 1;}
    _pw=argv[2];
    struct pam_conv pc={conv,NULL};
    pam_handle_t *ph=NULL;
    int r=pam_start("phosh",argv[1],&pc,&ph);
    if(r!=PAM_SUCCESS){pam_end(ph,r);return 1;}
    r=pam_authenticate(ph,0);
    if(r!=PAM_SUCCESS){pam_end(ph,r);return 1;}
    r=pam_acct_mgmt(ph,0);
    pam_end(ph,r);
    return r==PAM_SUCCESS?0:1;
}
CSRC
mkdir -p /usr/lib/gnome-mali
gcc -O2 -o /usr/lib/gnome-mali/pam-auth-helper /tmp/_pamhelper.c -lpam &&     chmod 4755 /usr/lib/gnome-mali/pam-auth-helper
rm -f /tmp/_pamhelper.c

# GNOME Shell lock screen extension
LOCK_EXT_DIR="/usr/share/gnome-shell/extensions/gnome-mali-lock@furios"
mkdir -p "$LOCK_EXT_DIR"
cp "$INSTALL_DIR/gnome-mali-lock-metadata.json" "$LOCK_EXT_DIR/metadata.json"
cp "$INSTALL_DIR/gnome-mali-lock-extension.js" "$LOCK_EXT_DIR/extension.js"

# Power key daemon
cp "$INSTALL_DIR/gnome-mali-power-daemon" /usr/local/bin/gnome-mali-power-daemon
chmod +x /usr/local/bin/gnome-mali-power-daemon

# Power key script (for manual use)
cp "$INSTALL_DIR/gnome-mali-power-key" /usr/local/bin/gnome-mali-power-key
chmod +x /usr/local/bin/gnome-mali-power-key

# Power key daemon systemd service
cat > /etc/systemd/system/gnome-mali-power.service << 'SVC'
[Unit]
Description=GNOME Mali power key handler
After=graphical.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gnome-mali-power-daemon
Restart=always
RestartSec=2
User=furios

[Install]
WantedBy=graphical.target
SVC

# logind override so power key sends Lock signal
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/zz-gnome-mali-power.conf << 'LOGIND'
[Login]
HandlePowerKey=lock
HandlePowerKeyLongPress=poweroff
LOGIND

# gsettings for the user - power button action nothing, custom keybinding
GSETTINGS="WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u furios) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u furios)/bus"
sudo -u furios env $GSETTINGS gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing' 2>/dev/null || true
sudo -u furios env $GSETTINGS gsettings set org.gnome.settings-daemon.plugins.media-keys screensaver "[]" 2>/dev/null || true
sudo -u furios env $GSETTINGS gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/power-lock/']" 2>/dev/null || true
sudo -u furios env $GSETTINGS gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/power-lock/ name 'Power Key' 2>/dev/null || true
sudo -u furios env $GSETTINGS gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/power-lock/ command '/usr/local/bin/gnome-mali-power-key' 2>/dev/null || true
sudo -u furios env $GSETTINGS gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/power-lock/ binding 'XF86PowerOff' 2>/dev/null || true

# Enable extension for the user
sudo -u furios env $GSETTINGS gsettings set org.gnome.shell enabled-extensions "$(sudo -u furios env $GSETTINGS gsettings get org.gnome.shell enabled-extensions 2>/dev/null | sed "s/]$/, 'gnome-mali-lock@furios']/;s/^@as \[\]$/['gnome-mali-lock@furios']/")" 2>/dev/null || true

# Brightness restore service (restores brightness if phone reboots while locked)
cat > /etc/systemd/system/gnome-mali-brightness-restore.service << 'SVC'
[Unit]
Description=Restore display brightness on boot
After=local-fs.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'SAVE=/tmp/gnome-mali-brightness.tmp; BL=/sys/class/leds/lcd-backlight/brightness; if [ -f "$SAVE" ]; then cat "$SAVE" > "$BL" 2>/dev/null; rm -f "$SAVE"; else echo 618 > "$BL" 2>/dev/null; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable gnome-mali-power.service
systemctl enable gnome-mali-brightness-restore.service
systemctl restart systemd-logind

# Record installed state
mkdir -p /var/lib/gnome-mali
date > "$STATE_FILE"

echo ""
echo "=== Installation complete! ==="
echo ""
echo "GNOME Mali is now available in the phrog session menu."
echo "Select 'GNOME Mali' to launch GNOME Shell with Mali GPU acceleration."
echo ""
echo "Pipeline: mutter → libEGL_libhybris.so (patched) → eglplatform_drmadapter.so → HWC2"
echo ""
echo "Session log:  /tmp/gnome-mali-session.log"
echo "Backups:      $BACKUP_DIR"
echo ""
echo "To uninstall, run: sudo ./uninstall-gnome-mali.sh"
