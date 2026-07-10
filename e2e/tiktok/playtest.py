#!/usr/bin/env python3
"""
playtest.py — drive the Time Dodge TikTok mini-game on a real device via Appium.

The mini-game is a <canvas> inside TikTok's TTMinis webview, so there is NO
accessible UI tree to query — automation is coordinate + pixel/OCR based.
The core mechanic is "time flows ONLY while you hold", so gameplay is expressed
with W3C pointer actions: pointerDown -> (move, pause)* -> pointerUp, held for
several seconds. A plain tap/swipe cannot express a multi-second hold-and-drag.

Prereqs (see README.md):
  - a REAL device (emulators are detected/blocked by TikTok), `adb devices` shows it
  - TikTok installed + logged in as a registered test user (manual, one-time)
  - the mini-game preview already opened (run launch.sh first, or pass --uri)
  - `appium` server running (default http://127.0.0.1:4723)
  - pip install -r requirements.txt ; tesseract optional for --ocr

Usage:
  python3 playtest.py --udid <serial> --shots ./shots [--uri <deep-link>] [--ocr]
"""
import argparse
import os
import subprocess
import sys
import time

from appium import webdriver
from appium.options.android import UiAutomator2Options
from selenium.webdriver.common.actions.action_builder import ActionBuilder
from selenium.webdriver.common.actions.pointer_input import PointerInput
from selenium.webdriver.common.actions import interaction

# --- Menu button centers as fractions of (width, height). Re-calibrate against
#     shots/01-menu.png if a tap misses on your device's aspect ratio. ---
MENU = {
    "endless": (0.50, 0.45),
    "trials":  (0.50, 0.63),
    "absorb":  (0.50, 0.74),
}
BACK = (0.13, 0.06)   # the "BACK" button seen on the TRIALS/level screens


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout.strip()


def make_driver(udid, appium_url):
    opts = UiAutomator2Options()
    opts.platform_name = "Android"
    opts.automation_name = "UiAutomator2"
    opts.udid = udid
    opts.no_reset = True          # keep the logged-in TikTok session
    opts.full_reset = False
    opts.new_command_timeout = 300
    # We drive the already-foreground TikTok app; don't let Appium relaunch it.
    opts.dont_stop_app_on_reset = True
    opts.auto_grant_permissions = True
    return webdriver.Remote(appium_url, options=opts)


class Pointer:
    def __init__(self, driver):
        self.d = driver
        self.w = driver.get_window_size()["width"]
        self.h = driver.get_window_size()["height"]

    def px(self, fx, fy):
        return int(fx * self.w), int(fy * self.h)

    def tap(self, fx, fy):
        x, y = self.px(fx, fy)
        a = ActionBuilder(self.d, mouse=PointerInput(interaction.POINTER_TOUCH, "t"))
        a.pointer_action.move_to_location(x, y).pointer_down().pause(0.05).pointer_up()
        a.perform()

    def hold_drag(self, waypoints, hold_s=4.0):
        """waypoints: list of (fx, fy) in [0,1]. Presses at the first point, moves
        through the rest while holding, spreading `hold_s` seconds across the moves,
        then releases. This is the 'time flows while held' gesture."""
        pts = [self.px(fx, fy) for fx, fy in waypoints]
        a = ActionBuilder(self.d, mouse=PointerInput(interaction.POINTER_TOUCH, "t"))
        x0, y0 = pts[0]
        a.pointer_action.move_to_location(x0, y0).pointer_down()
        moves = max(1, len(pts) - 1)
        per = hold_s / moves
        for (x, y) in pts[1:]:
            a.pointer_action.move_to_location(x, y).pause(per)
        a.pointer_action.pointer_up()
        a.perform()


def shot(driver, shots_dir, name):
    os.makedirs(shots_dir, exist_ok=True)
    path = os.path.join(shots_dir, name)
    driver.get_screenshot_as_file(path)
    print("  shot ->", path)
    return path


def ocr(path):
    try:
        out = subprocess.run(["tesseract", path, "stdout"],
                             capture_output=True, text=True, timeout=30).stdout
        return out.upper()
    except Exception as e:
        print("  (ocr skipped:", e, ")")
        return ""


def assert_contains(driver, shots_dir, name, needle, do_ocr):
    path = shot(driver, shots_dir, name)
    if not do_ocr:
        return None
    text = ocr(path)
    ok = needle.upper() in text
    print(f"  ASSERT '{needle}' in HUD: {'PASS' if ok else 'FAIL'}")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--udid", default=os.environ.get("ANDROID_SERIAL", ""))
    ap.add_argument("--appium", default="http://127.0.0.1:4723")
    ap.add_argument("--shots", default="./shots")
    ap.add_argument("--uri", default="", help="preview deep link; launched via adb before driving")
    ap.add_argument("--ocr", action="store_true", help="assert HUD text via tesseract")
    args = ap.parse_args()

    if not args.udid:
        args.udid = sh("adb", "get-serialno")
    if not args.udid or args.udid == "unknown":
        print("no device serial; is a real device connected? (adb devices)", file=sys.stderr)
        sys.exit(1)

    if args.uri:
        print("launching preview deep link ...")
        subprocess.run([os.path.join(os.path.dirname(__file__), "launch.sh"), args.uri],
                       check=False, env={**os.environ, "ANDROID_SERIAL": args.udid})
        time.sleep(6)

    driver = make_driver(args.udid, args.appium)
    results = []
    try:
        p = Pointer(driver)
        time.sleep(3)  # let the canvas paint
        shot(driver, args.shots, "01-menu.png")

        # --- ENDLESS: hold and weave to dodge; HUD should show STOLEN + a timer ---
        print("[ENDLESS]")
        p.tap(*MENU["endless"]); time.sleep(1.5)
        p.hold_drag([(0.5, 0.6), (0.6, 0.5), (0.4, 0.55), (0.55, 0.4), (0.45, 0.5)], hold_s=5)
        results.append(assert_contains(driver, args.shots, "02-endless.png", "STOLEN", args.ocr))
        time.sleep(1)
        driver.back()  # return toward menu (or use BACK coord if needed)
        time.sleep(1.5)
        p.tap(*BACK); time.sleep(1)

        # --- TRIALS: level select should render; open level 1 ---
        print("[TRIALS]")
        p.tap(*MENU["trials"]); time.sleep(1.5)
        shot(driver, args.shots, "03-trials-select.png")
        p.tap(0.15, 0.36)  # level 1 tile (top-left of the grid); calibrate if needed
        time.sleep(1.5)
        p.hold_drag([(0.5, 0.6), (0.5, 0.45), (0.6, 0.5)], hold_s=3)
        shot(driver, args.shots, "04-trials-play.png")
        driver.back(); time.sleep(1.5)
        p.tap(*BACK); time.sleep(1)

        # --- ABSORB: eat small (green) rocks; HUD should show MASS/EATEN ---
        print("[ABSORB]")
        p.tap(*MENU["absorb"]); time.sleep(1.5)
        p.hold_drag([(0.5, 0.6), (0.55, 0.5), (0.45, 0.55), (0.5, 0.45)], hold_s=5)
        results.append(assert_contains(driver, args.shots, "05-absorb.png", "MASS", args.ocr))

        print("\ndone. screenshots in", args.shots)
        if args.ocr:
            passed = sum(1 for r in results if r)
            total = sum(1 for r in results if r is not None)
            print(f"OCR assertions: {passed}/{total} passed")
            sys.exit(0 if passed == total else 1)
    finally:
        driver.quit()


if __name__ == "__main__":
    main()
