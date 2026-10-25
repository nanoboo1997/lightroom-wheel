# Lightroom Wheel

A free, experimental macOS helper: **hover a Basic slider in Lightroom Classic and turn the mouse wheel to adjust it**.

Native Swift helper + a small Lua plug-in. Slider positions come from on-device text recognition; adjustment values are read and written through the Lightroom SDK. No subscription, cloud service or third-party runtime dependencies.

**Status: early prototype.** Physical mouse testing confirmed that hovering Exposure changes Exposure after the pointer-coordinate fix. This is not a claim that every slider, display configuration or Lightroom version has been validated. The helper UI is currently in Thai.

[คู่มือภาษาไทย](README-TH.md) · [Test evidence and limitations](TEST-RESULTS.txt)

## Requirements

- Apple Silicon Mac. Build target: macOS 14.2 or newer; older supported OS versions have not been tested.
- An installed and licensed copy of Adobe Lightroom Classic. Tested with Classic 15.6 and a JPEG photo on a MacBook M4.
- English **Develop → Basic** panel, with **exactly one photo selected**.
- Accessibility and Screen Recording permissions for the helper.

The helper is free; it does not include Lightroom or replace Adobe's licensing.

## Install

1. Download the ZIP from [Releases](https://github.com/nanoboo1997/lightroom-wheel/releases) and extract the complete `LightroomWheel` folder into a writable location.
2. Keep `Lightroom Wheel.app` and `Lightroom Wheel.lrplugin` beside each other.
3. In Classic, open **File → Plug-in Manager → Add**, select `Lightroom Wheel.lrplugin`, and enable it. If needed, choose **File → Plug-in Extras → Start Lightroom Wheel Bridge** or reload it in Plug-in Manager.
4. Open the helper. Grant **Accessibility** and **Screen Recording** to **Lightroom Wheel** in macOS System Settings, then reopen the helper.
5. The helper starts automatically when permissions and the plug-in are ready. Switch to Classic, select one photo in Develop, and hover the slider track before turning the wheel.

For use without an external SSD, keep the complete folder in `~/Applications/LightroomWheel` on the internal disk and select that plug-in in Classic. Disable the old external-disk plug-in after moving. To launch at login, add the installed app to **System Settings → General → Login Items → Open at Login** on each Mac.

Automatic startup is available in the source on `main`; the published v0.2.0 ZIP still requires clicking Start. Build from source for the updated behavior. Startup retries every five seconds while waiting for permissions or the plug-in, without activating Classic. Pause lasts for the current session; reopening starts automatically again. Quit exits until you open the app or next log in.

The app is ad-hoc signed, **not notarized**. macOS may require explicit approval to open a downloaded build. You can also build from the source below. Rebuilding changes its signature and may require refreshing permissions for this app.

## Controls

| Action | Result |
| --- | --- |
| Wheel up / down | Increase / decrease the hovered slider |
| Shift + wheel | Fine Exposure adjustment: 0.01 instead of 0.05 |
| Control + wheel | Five times the normal step |
| Option + wheel | Normal panel scrolling |
| Menu-bar mouse icon | Show, pause or quit the helper |

Some mice send several wheel units for one physical detent. After scrolling the panel or changing photos, allow about a second for the positions to refresh. The helper only adjusts while Classic is foregrounded in Develop.

Configured Basic controls: Temp, Tint, Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Texture, Clarity, Dehaze, Vibrance and Saturation. **RAW temperature in Kelvin, Masks, Tone Curve and Color Mixer are not supported.**

## Privacy and behavior

The helper captures a narrow right-side region of the Classic window to identify control labels. It does not save those captures or send them online. macOS grants a broader Screen Recording permission than this capture region; this code limits its own capture to the controls region.

The app and plug-in exchange local command/reply/state files in `Lightroom Wheel.lrplugin/bridge/`. Those files contain a catalog-local photo ID and adjustment values. They are excluded from Git and release ZIPs. Optional developer diagnostics contain recognized control text and coordinates.

Adjustments change Lightroom's catalog settings through the SDK; the original JPEG is not overwritten. The plug-in rejects commands for a different photo or multiple selected photos. It does not alter Adobe's application files or install a login item.

## Build and test

Install Apple's Xcode Command Line Tools, then run:

```sh
./test.sh
./build.sh
python3 package.py
```

The app and plug-in are assembled in `dist/LightroomWheel/`; the ZIP is created in `dist/`. Building here does not replace another installed copy. Do not use the build output as a live plug-in folder while rebuilding it.

Tests cover value bounds, precision, wheel accumulation, panel context, global pointer coordinates and duplicate tooltip labels. A separate synthetic numeric OCR test is retained from the earlier prototype; production values now come from the SDK. `Source/TestOCR.swift` is a legacy manual screenshot-fixture utility; no private screenshot fixtures are included.

GitHub Actions builds the app and runs these tests on macOS. It cannot perform live Lightroom testing. The helper's Exposure self-test temporarily adds 0.05 and attempts to restore the original value; keep Classic foregrounded for the entire test.

## Known limitations

- OCR can miss labels when the panel moves, is obscured, or uses a different layout/font size. Multiple displays and other scaling configurations are not validated.
- This is slower than Lightroom's native controls; it is not a finished commercial-grade input driver.
- Keep the app's folder available and writable while using it, including any external SSD.
- Test on a Virtual Copy before relying on it for important edits. Report the macOS/Classic versions and the slider involved when filing a bug; avoid attaching private photo or catalog data.

## License

MIT. Independent community project; not affiliated with or endorsed by Adobe. Lightroom is an Adobe trademark.
