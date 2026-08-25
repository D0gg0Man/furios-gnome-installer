import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const PAM_HELPER = '/usr/lib/gnome-mali/pam-auth-helper';
const BRIGHTNESS_PATH = '/sys/class/leds/lcd-backlight/brightness';

// ── Customization ─────────────────────────────────────────────────────────────
const CLOCK_FONT_SIZE  = 80;   // clock digits (px)
const DATE_FONT_SIZE   = 22;   // date string (px)
const PIN_FONT_SIZE    = 28;   // pin dots (px)
const STATUS_FONT_SIZE = 20;   // "Enter PIN" / "Wrong PIN" (px)
const BUTTON_FONT_SIZE = 44;   // numpad digits (px)
const BUTTON_W         = 270;  // numpad button width (px)
const BUTTON_H         = 150;  // numpad button height (px)
const BUTTON_GAP       = 18;   // gap between buttons (px)
const NUMPAD_OFFSET    = 0;    // shift numpad up(-) or down(+) from center
// ─────────────────────────────────────────────────────────────────────────────

let _overlay       = null;
let _pinGroup      = null;
let _modalPushed   = false;
let _locked        = false;
let _displayOn     = false;
// brightness saved to BRIGHTNESS_SAVE file

const BRIGHTNESS_SAVE = '/tmp/gnome-mali-brightness.tmp';

function readBrightness() {
    try {
        let [ok, out] = GLib.spawn_command_line_sync('cat ' + BRIGHTNESS_PATH);
        if (ok && out && out.length > 0) {
            let v = parseInt(new TextDecoder().decode(out).trim());
            if (!isNaN(v) && v > 0) return v;
        }
    } catch(e) {}
    return 618;
}

function saveBrightness(val) {
    try {
        GLib.spawn_command_line_async(
            'bash -c "echo ' + Math.round(val) + ' > ' + BRIGHTNESS_SAVE + '"');
    } catch(e) {}
}

function getSavedBrightness() {
    try {
        let [ok, out] = GLib.spawn_command_line_sync('cat ' + BRIGHTNESS_SAVE);
        if (ok && out && out.length > 0) {
            let v = parseInt(new TextDecoder().decode(out).trim());
            if (!isNaN(v) && v > 0) return v;
        }
    } catch(e) {}
    return 618;
}

function setBrightness(val) {
    try {
        GLib.spawn_command_line_async(
            'bash -c "echo ' + Math.round(val) + ' > ' + BRIGHTNESS_PATH + ' 2>/dev/null"');
    } catch(e) {}
}

function setVisible(v) {
    _displayOn = v;
    if (!_overlay || !_pinGroup) return;
    if (v) {
        setBrightness(getSavedBrightness());
        _pinGroup.show();
        _pinGroup.ease({ opacity: 255, duration: 250,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onComplete: () => {
                // Reposition clock after widgets are allocated
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
                    if (_overlay && _overlay._tickFn) _overlay._tickFn();
                    return GLib.SOURCE_REMOVE;
                });
            }
        });
    } else {
        _pinGroup.ease({ opacity: 0, duration: 200,
            mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onComplete: () => {
                if (_pinGroup) _pinGroup.hide();
                setBrightness(0);
            }
        });
    }
}

function doUnlock() {
    log('gnome-mali-lock: doUnlock');
    _locked = false;
    _pinGroup = null;
    try { GLib.spawn_command_line_async('rm -f /tmp/gnome-mali-lock-state.locked /tmp/gnome-mali-lock-state.showing'); } catch(e) {}
    if (!_overlay) { setBrightness(getSavedBrightness()); return; }
    let ov = _overlay; _overlay = null;
    try { if (_modalPushed) { Main.popModal(ov); _modalPushed = false; } } catch(e) {}
    try { if (ov._clockId) GLib.source_remove(ov._clockId); } catch(e) {}
    setBrightness(getSavedBrightness());
    ov.ease({ opacity: 0, duration: 200,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        onComplete: () => {
            try { ov.get_parent().remove_child(ov); } catch(e) {}
            try { ov.destroy(); } catch(e) {}
        }
    });
}

function buildUI() {
    let W = global.screen_width, H = global.screen_height;

    let ov = new St.Widget({
        style: 'background-color: #000000;',
        reactive: true, can_focus: true,
        x: 0, y: 0, width: W, height: H, opacity: 255,
    });

    const BW = BUTTON_W, BH = BUTTON_H, GAP = BUTTON_GAP;
    const GW = 3*BW + 2*GAP;
    const GX = Math.floor((W - GW) / 2);
    const GY = Math.floor(H/2) - Math.floor(1.5*(BH+GAP)) + NUMPAD_OFFSET;

    // PIN group — hidden until power button wakes screen
    let pg = new St.Widget({ x: 0, y: 0, width: W, height: H, opacity: 0 });
    pg.hide();
    ov.add_child(pg);
    _pinGroup = pg;

    // Clock
    let clk = new St.Label({
        style: `font-size: ${CLOCK_FONT_SIZE}px; color: #ffffff; font-weight: 300;`
    });
    pg.add_child(clk);

    // Date
    let dateLbl = new St.Label({
        style: `font-size: ${DATE_FONT_SIZE}px; color: #aaaaaa;`
    });
    pg.add_child(dateLbl);

    function tick() {
        let d = new Date();
        clk.set_text(
            d.getHours().toString().padStart(2,'0') + ':' +
            d.getMinutes().toString().padStart(2,'0'));
        let days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
        let months = ['January','February','March','April','May','June',
                      'July','August','September','October','November','December'];
        dateLbl.set_text(days[d.getDay()] + ', ' + d.getDate() + ' ' + months[d.getMonth()]);
        // Center after layout
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            clk.set_position(Math.floor(W/2 - clk.width/2), GY - 450);
            dateLbl.set_position(Math.floor(W/2 - dateLbl.width/2), GY - 200);
            return GLib.SOURCE_REMOVE;
        });
        return GLib.SOURCE_CONTINUE;
    }
    tick();
    // Re-run after 100ms to ensure layout is settled
    ov._tickFn = tick;
    ov._clockId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, tick);

    // PIN dots
    let dots = new St.Label({
        style: `font-size: ${PIN_FONT_SIZE}px; color: #ffffff;`, text: ''
    });
    pg.add_child(dots);

    // Status
    let status = new St.Label({
        style: `font-size: ${STATUS_FONT_SIZE}px; color: #888888;`, text: 'Enter PIN'
    });
    pg.add_child(status);

    function reposition() {
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            dots.set_position(Math.floor(W/2 - dots.width/2), GY - 105);
            status.set_position(Math.floor(W/2 - status.width/2), GY - 55);
            return GLib.SOURCE_REMOVE;
        });
    }
    reposition();

    let pin = '';
    function redrawDots() {
        dots.set_text(pin.length > 0 ? ('● ').repeat(pin.length).trimEnd() : '');
        reposition();
    }
    function add(d) { pin += d; redrawDots(); }
    function del() { if (pin.length > 0) { pin = pin.slice(0,-1); redrawDots(); } }

    function tryAuth() {
        status.set_text('Checking...');
        status.set_style(`font-size: ${STATUS_FONT_SIZE}px; color: #888888;`);
        reposition();
        let p = pin;
        try {
            let [ok, pid] = GLib.spawn_async(null,
                [PAM_HELPER, GLib.get_user_name(), p], null,
                GLib.SpawnFlags.DO_NOT_REAP_CHILD |
                GLib.SpawnFlags.STDOUT_TO_DEV_NULL |
                GLib.SpawnFlags.STDERR_TO_DEV_NULL, null);
            if (ok) {
                GLib.child_watch_add(GLib.PRIORITY_DEFAULT, pid, (pp, st) => {
                    let success = false;
                    try { GLib.spawn_check_wait_status(st); success = true; } catch(e) {}
                    GLib.spawn_close_pid(pp);
                    if (success) { doUnlock(); return; }
                    pin = ''; redrawDots();
                    status.set_text('Wrong PIN');
                    status.set_style(`font-size: ${STATUS_FONT_SIZE}px; color: #ff5555;`);
                    reposition();
                    // Shake animation
                    let btns = [];
                    pg.get_children().forEach(c => { if (c instanceof St.Button) btns.push(c); });
                    let ox = btns.map(b => b.x);
                    let sh = [15,-15,10,-10,5,-5,0]; let si = 0;
                    function shake() {
                        if (si >= sh.length) { btns.forEach((b,i) => b.set_x(ox[i])); return; }
                        btns.forEach((b,i) => b.set_x(ox[i] + sh[si])); si++;
                        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 45,
                            () => { shake(); return GLib.SOURCE_REMOVE; });
                    }
                    shake();
                    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
                        status.set_text('Enter PIN');
                        status.set_style(`font-size: ${STATUS_FONT_SIZE}px; color: #888888;`);
                        reposition();
                        return GLib.SOURCE_REMOVE;
                    });
                });
                return;
            }
        } catch(e) { log('lock err: ' + e); }
    }

    function btnFeedback(btn, down) {
        btn.ease({
            scale_x: down ? 0.88 : 1.0,
            scale_y: down ? 0.88 : 1.0,
            duration: down ? 60 : 150,
            mode: down ? Clutter.AnimationMode.EASE_OUT_QUAD
                       : Clutter.AnimationMode.EASE_OUT_BACK,
        });
        btn.set_style(down ? btn._sd : btn._su);
    }

    [['1','2','3'],['4','5','6'],['7','8','9'],['⌫','0','✓']].forEach((row, r) => {
        row.forEach((lbl, c) => {
            let isAct = lbl === '⌫' || lbl === '✓';
            let su = `background-color:${isAct?'#2a2a5e':'#161636'}; border-radius:20px; font-size:${BUTTON_FONT_SIZE}px; color:#ffffff; border:1px solid #333366;`;
            let sd = `background-color:${isAct?'#4a4a9e':'#363676'}; border-radius:20px; font-size:${BUTTON_FONT_SIZE}px; color:#ffffff; border:1px solid #5555aa;`;
            let btn = new St.Button({
                label: lbl, style: su,
                reactive: true, can_focus: false, track_hover: false,
                width: BW, height: BH,
            });
            btn._su = su; btn._sd = sd;
            btn.set_pivot_point(0.5, 0.5);
            btn.set_position(GX + c*(BW+GAP), GY + r*(BH+GAP));
            btn.connect('button-press-event',   () => { btnFeedback(btn, true);  return Clutter.EVENT_PROPAGATE; });
            btn.connect('button-release-event', () => { btnFeedback(btn, false); return Clutter.EVENT_PROPAGATE; });
            btn.connect('touch-event', (b, ev) => {
                let t = ev.type();
                if (t === Clutter.EventType.TOUCH_BEGIN)
                    btnFeedback(btn, true);
                else if (t === Clutter.EventType.TOUCH_END || t === Clutter.EventType.TOUCH_CANCEL)
                    btnFeedback(btn, false);
                return Clutter.EVENT_PROPAGATE;
            });
            btn.connect('clicked', () => {
                btnFeedback(btn, false);
                if (lbl === '⌫') del();
                else if (lbl === '✓') { if (pin.length > 0) tryAuth(); }
                else add(lbl);
            });
            pg.add_child(btn);
        });
    });

    ov.connect('key-press-event', (a, ev) => {
        let k = ev.get_key_symbol();
        if (k >= Clutter.KEY_0 && k <= Clutter.KEY_9) add(String.fromCharCode(k));
        else if (k === Clutter.KEY_Return || k === Clutter.KEY_KP_Enter) { if (pin.length > 0) tryAuth(); }
        else if (k === Clutter.KEY_BackSpace) del();
        return Clutter.EVENT_STOP;
    });

    return ov;
}

function lock() {
    log('gnome-mali-lock: lock() _locked=' + _locked);
    if (_locked) {
        // Already locked — power button toggles display
        if (!_displayOn) {
            setVisible(true);
            if (_overlay) _overlay.grab_key_focus();
        } else {
            setVisible(false);
        }
        return;
    }
    _locked = true;
    _displayOn = false;
    let bright = readBrightness();
    saveBrightness(bright);
    _overlay = buildUI();
    Main.uiGroup.add_child(_overlay);
    try { if (Main.pushModal(_overlay)) _modalPushed = true; } catch(e) { log('pushModal err:' + e); }
    try { GLib.spawn_command_line_async('touch /tmp/gnome-mali-lock-state.locked'); } catch(e) {}
    setBrightness(0);
    log('gnome-mali-lock: locked pushModal=' + _modalPushed + ' savedBright=' + _savedBright);
}

export default class GnomeMaliLock {
    enable() {
        log('gnome-mali-lock: pam=' + GLib.file_test(PAM_HELPER, GLib.FileTest.EXISTS));
        this._lc = Gio.DBus.system.signal_subscribe(
            null, 'org.freedesktop.login1.Session', 'Lock', null, null,
            Gio.DBusSignalFlags.NONE,
            () => { log('gnome-mali-lock: Lock signal'); lock(); });
        this._uc = Gio.DBus.system.signal_subscribe(
            null, 'org.freedesktop.login1.Session', 'Unlock', null, null,
            Gio.DBusSignalFlags.NONE,
            () => { log('gnome-mali-lock: Unlock signal'); doUnlock(); });
        this._bc = Gio.DBus.session.signal_subscribe(
            null, 'org.gnome.mali.Lock', 'Blank', '/org/gnome/mali/lock', null,
            Gio.DBusSignalFlags.NONE,
            () => { log('gnome-mali-lock: Blank'); if (_locked) setVisible(false); });
        this._wc = Gio.DBus.session.signal_subscribe(
            null, 'org.gnome.mali.Lock', 'WakeUp', '/org/gnome/mali/lock', null,
            Gio.DBusSignalFlags.NONE,
            () => {
                log('gnome-mali-lock: WakeUp');
                if (_locked) { setVisible(true); if (_overlay) _overlay.grab_key_focus(); }
            });
        log('gnome-mali-lock: enabled');
    }
    disable() {
        if (this._lc) Gio.DBus.system.signal_unsubscribe(this._lc);
        if (this._uc) Gio.DBus.system.signal_unsubscribe(this._uc);
        if (this._bc) Gio.DBus.session.signal_unsubscribe(this._bc);
        if (this._wc) Gio.DBus.session.signal_unsubscribe(this._wc);
        doUnlock();
    }
}
