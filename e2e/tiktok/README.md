# TikTok Mini-Game E2E Playtest Runbook

Automate the **TikTok in-app preview → Time Dodge mini-game → drive gameplay →
screenshot/assert** flow, so the `miniprogram/tiktok/` build can be verified in the
*real* TTMinis runtime (real `clientKey` auth, rewarded-video ad, real touch), not
only in the headless-browser equivalent (`miniprogram/test/run.js` + Playwright).

> **Why not just an emulator?** TikTok actively detects Android emulators and the
> Appium/UiAutomator process, and can refuse to load the mini-game or block login.
> This runbook therefore targets a **real device** first (local phone or a
> cloud *real-device* farm). An x86 accelerated emulator is documented only as a
> last-resort fallback — expect detection.

---

## 0. The one blocker automation can't own: the test-user login

The portal preview is gated on *"your TikTok account is added as a test user."*
Logging that account in requires SMS OTP / captcha / device risk-control that
TikTok deliberately makes bot-hostile. **Do the login once, by hand**, on the
device, and keep the session alive. Everything after login is scripted here.

So the split is:

| Step | Who | How |
|------|-----|-----|
| Install TikTok + log in as the test user | **You (once, manual)** | real device or farm's interactive session |
| Open the mini-game preview | script | `adb` deep-link (§2) or Maestro menu nav |
| Drive gameplay (hold-drag, all 3 modes) | script | Appium W3C pointer actions (§3) |
| Capture screenshots + assert "game is live" | script | screencap + optional OCR (§3) |

---

## 1. Pick where the device runs

| Option | Emulator-detection risk | Cost | One-time manual login | Recommendation |
|--------|------------------------|------|----------------------|----------------|
| **Local physical Android + USB `adb`** | none (real device) | free | trivial (you hold the phone) | **best if you have an Android phone** |
| **Cloud real-device farm** — BrowserStack App Automate, AWS Device Farm, Sauce Labs | none (real device) | paid | via the farm's *interactive/manual* session, then hand the session to the automated run | best if no local phone |
| **Genymotion Cloud (x86, accelerated)** | **high** — it's still an emulator | paid | scripted, but login may be blocked | fallback only |
| Local AVD / Redroid **in this container** | n/a | — | — | **impossible here** (no `/dev/kvm`, no binder — see repo chat) |

Everything below assumes `adb` can see the device:

```bash
adb devices           # -> one device/emulator in "device" state
adb shell getprop ro.product.model
```

For a cloud farm, replace direct `adb`/Appium `http://127.0.0.1:4723` with the
farm's remote Appium endpoint + capabilities (see the farm's docs); the flow
scripts are identical.

---

## 2. Enter the preview without scanning the QR

The QR the developer portal shows just encodes a **preview deep link**. On a
device already logged in as the test user you can open it directly instead of
pointing a camera at a screen:

```bash
# TikTok global package = com.zhiliaoapp.musically
# Put the decoded QR URI in PREVIEW_URI (see tools/decode_qr note below).
export PREVIEW_URI='<decoded-qr-deep-link>'
./launch.sh "$PREVIEW_URI"
```

`launch.sh` runs `am start -a android.intent.action.VIEW -d "$PREVIEW_URI" -p
com.zhiliaoapp.musically`. If the URI is a TikTok custom scheme (`snssdk*://`,
`aweme://`) drop the `-p` filter and let the system resolve it.

**Decoding the QR:** any offline QR reader works; from a photo of the portal use
e.g. `zbarimg qr.png`, an online-free decoder, or the portal's *copy link*
button if present. (In this repo's container we attempted a `jimp`+`jsQR` decode
of the uploaded photo — see chat for the result; a clean screenshot of the QR
decodes far more reliably than an angled phone photo.)

If deep-linking is flaky, fall back to driving TikTok's own **Developer →
Preview** entry with the Maestro flow in `flow.yaml`.

---

## 3. Drive gameplay + capture

`playtest.py` (Appium, UiAutomator2) does, once the preview mini-game is open:

1. Wait for the canvas to paint (fixed settle + a non-blank screenshot check).
2. **Menu → ENDLESS/TRIALS/ABSORB** by tapping fixed normalized coordinates.
3. In-game **hold-drag**: W3C `pointerDown → (move,pause)* → pointerUp`, held for
   several seconds — this is the "time flows only while held" mechanic, which a
   plain `tap`/`swipe` can't express.
4. Screenshot after every step into `./shots/`.
5. Optional **OCR assertion** (tesseract) that the live HUD text is present
   (`STOLEN` in ENDLESS, `MASS` in ABSORB) — proof the real TTMinis runtime
   booted the engine, not a blank/error page.

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
# start the Appium server in another shell:  appium
python3 playtest.py --udid "$(adb get-serialno)" --shots ./shots
```

Coordinates are **normalized (0..1)** and multiplied by the real screen size the
script reads from the device, so the same flow works across resolutions. If a
mode button misses on your device, adjust the fractions in `MENU` at the top of
`playtest.py` against the first `shots/01-menu.png`.

---

## 4. What "meets expectations" means here

The headless-browser pass already proved engine logic + rendering (31/31
invariants, all three modes). This on-device pass is specifically to confirm the
things the browser **can't**:

- [ ] Mini-game loads inside TikTok with the **real `clientKey`** (no auth error).
- [ ] Touch mapping feels right (orb tracks finger delta ×1.5, not covered).
- [ ] **ABSORB rewarded-video ad**: first big hit → "CANCEL THIS HIT?" → **YES**
      plays the TTMinis ad → *watched to end waives the chip*; quit mid-ad → normal
      25% chip. (Confirm the `isEnded`/close callback fields — `SHIPPING.md` §8.7
      `NOTE(ship)`.)
- [ ] `localStorage` persistence (`timedodge_best`, `td_absorb_best`, level stars)
      survives an app kill/relaunch.
- [ ] Frame pacing acceptable on the target device.

---

## 5. Honest limitations

- **Login can't be fully scripted** (OTP/captcha) — manual once, per §0.
- **Emulator = likely blocked.** Real device strongly preferred.
- **Canvas games have no accessible UI tree** — automation is coordinate + pixel/OCR
  based, so it's brittle to layout changes. Re-calibrate `MENU` coords if the UI moves.
- These scripts are a **runbook to run on your device**; they were syntax-checked
  but not executed against a live TikTok session from this container (no device here).
