# ScreenSense: Walkthrough & User Guide

This guide describes how to build, run, load the Chrome extension, grant permissions, and test both Phase 1 (Voice/Paste) and Phase 2 (Screen Context Engine).

---

## 1. Building the Project

### Development Build & Test Suite
```bash
# Optional: Activate conda environment
conda activate screensense-env

# Run all 20 automated unit tests
swift test

# Build debug binary
swift build
```

### Packaging as a macOS App Bundle (.app)
```bash
./scripts/build_app.sh
```
This produces `build/ScreenSense.app` signed for local execution.

---

## 2. Installing the Chrome Extension

1. Open Google Chrome.
2. Navigate to `chrome://extensions`.
3. Enable **Developer mode** (toggle in top right).
4. Click **"Load unpacked"** in the top left.
5. Select the `Extension` directory from this repository:
   ```text
   /Users/sj/Documents/Screensense/Extension
   ```
6. The **ScreenSense Browser Bridge** extension will now be loaded with its icon in the Chrome toolbar.

---

## 3. Running ScreenSense

Run the packaged application:
```bash
open build/ScreenSense.app
```

ScreenSense will launch as a menu bar accessory (look for the waveform icon 🎙️ in your macOS top menu bar).

---

## 4. Granting & Verifying System Permissions

Click the ScreenSense menu bar icon to open the status popup. The checklist shows real-time status without caching stale permissions:

1. **Microphone**: Click **"Request Permissions"** or grant in **System Settings → Privacy & Security → Microphone**.
2. **Speech Recognition**: Grant when prompted or in **System Settings → Privacy & Security → Speech Recognition**.
3. **Accessibility**: Click **"Settings"** and toggle **ScreenSense** ON in **System Settings → Privacy & Security → Accessibility** (for `⌘V` paste simulation). Then click **"Refresh"** in the menu bar popover to immediately re-query `AXIsProcessTrustedWithOptions` and observe the badge turn to ✅.
4. **Screen Recording**: Click **"Settings"** and toggle **ScreenSense** ON in **System Settings → Privacy & Security → Screen Recording** (for ScreenCaptureKit capture). Click **"Refresh"** to verify.

---

## 5. Phase 2 Verification & Manual Testing

### Test Case 1: Viewport DOM Extraction with Test Page
1. Open the included test page in Chrome:
   ```bash
   open -a "Google Chrome" TestPage/index.html
   ```
2. Scroll to the middle of the page (e.g., Section 2 or Section 3).
3. Observe the bottom-right **ScreenSense Live HUD** updating visible element counts dynamically.
4. Open the **ScreenSense** menu bar popover and switch to the **"Screen Context (Debug)"** tab.
5. Click **"Fetch DOM"** or **"Fusion"**.
6. **Verification**:
   - The UI displays: `Source: UNIFIED` (or `DOM`).
   - The element list shows only elements currently inside the viewport (e.g. Paragraphs 4–6), in top-to-bottom reading order.
   - Visibility percentages (e.g., `100% visible`, `75% visible`) match the viewport intersection.
   - Elements with `display: none`, `visibility: hidden`, `opacity: 0`, and zero dimensions are **not** present in the list.

### Test Case 2: Wikipedia Real-World Viewport Test
1. Open any Wikipedia article (e.g., [https://en.wikipedia.org/wiki/Swift_(programming_language)](https://en.wikipedia.org/wiki/Swift_(programming_language))).
2. Scroll to a specific section (e.g., "History" or "Features").
3. Click **"Fetch DOM"** or **"Fusion"** in the ScreenSense menu bar view.
4. **Verification**:
   - ScreenSense extracts exactly the visible headings, paragraphs, and list items.
   - Spatial ordering matches the page's visual layout.

### Test Case 3: ScreenCaptureKit On-Demand Capture
1. In the ScreenSense menu bar popover, switch to **"Screen Context (Debug)"**.
2. Click **"Capture Screen"**.
3. **Verification**:
   - ScreenCaptureKit captures the main display/active window.
   - A visual thumbnail appears in the menu bar popover under "Visual Confirmation".
   - Resolution and active application metadata are updated.

### Test Case 4: Phase 1 Voice Paste Regression
1. Open **TextEdit**, type `ScreenSense Paste Test`, copy it (`⌘C`).
2. Move cursor to a blank line.
3. Press **`⌥ ⇧ Space`** and say **`paste`**.
4. **Verification**: `⌘V` is synthesized and text appears at cursor.

---

## 6. Automated Test Suite

### Run Swift Automated Tests (20 Tests):
```bash
swift test
```

### Run Chrome Extension Automated Tests (10 Tests):
```bash
node Extension/test/visibility-analyzer.test.js
```

### Test Coverage Summary:
- **`visibility-analyzer.test.js` (10 JS Tests)**:
  - Standard visible element detection
  - Self `aria-hidden="true"` exclusion
  - Ancestor `aria-hidden="true"` recursive exclusion
  - Self and ancestor `[hidden]` attribute exclusion
  - `display: none` exclusion
  - `visibility: hidden` exclusion
  - Self and ancestor `opacity: 0` exclusion
  - Zero-dimension (`0x0`, `0x50`, `50x0`) element exclusion
  - Outside viewport (above/below/left/right) exclusion
  - Partially visible element calculation (`50% visible`)
- **`ContextModelTests`**: JSON serialization/deserialization of `VisibleContext`, spatial reading order sorting (`spatiallySortedElements`), and type-based filtering.
- **`ContextFusionTests`**: Fusion logic for DOM only, ScreenCaptureKit only, and unified multimodal combination.
- **`LocalBrowserBridgeTests`**: Local HTTP bridge context propagation and `DOMContextProvider` delegation.
- **`CommandParserTests`**: Spoken text normalization, exact `"paste"` matching, natural language variations (`"paste here"`, `"please paste"`), and unsupported command rejection.
- **`PasteManagerTests`**: Keystroke simulation abstraction, error propagation on missing Accessibility permissions, and context execution.
- **`CoordinatorTests`**: End-to-end hotkey registration, voice session lifecycle, and state machine transitions.

---

## 7. Known Limitations (Phase 2 Scope)

- DOM extraction requires Google Chrome with the ScreenSense unpacked extension loaded.
- For non-browser apps, context is captured via ScreenCaptureKit (ready for Phase 3 OCR/Vision processing).
- The Developer Debug View in the menu bar is for inspection/validation in Phase 2; the final user-facing overlay will be built in later phases.
