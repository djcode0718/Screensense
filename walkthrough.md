# ScreenSense: Walkthrough & User Guide

This guide describes how to build, run, grant permissions, and test ScreenSense Phase 1.

---

## 1. Building the Project

You can build the project using Swift Package Manager:

### Development Build & Test Suite
```bash
# Activate conda environment if preferred
conda activate screensense-env

# Run automated tests
swift test

# Build debug binary
swift build
```

### Packaging as a macOS App Bundle (.app)
macOS requires an `.app` bundle with `Info.plist` for system permission prompts (Microphone and Speech Recognition). A packaging script is provided:

```bash
./scripts/build_app.sh
```
This produces `build/ScreenSense.app` signed for local execution.

---

## 2. Running ScreenSense

Run the packaged application:
```bash
open build/ScreenSense.app
```

Alternatively, you can run directly from SPM:
```bash
swift run ScreenSense
```

ScreenSense will launch as a menu bar accessory (look for the waveform icon 🎙️ in your macOS top menu bar).

---

## 3. Granting Permissions

Click on the ScreenSense menu bar icon to open the status popup. You will see the **System Permissions** checklist:

1. **Microphone**: Click **"Request All Permissions"** or grant in **System Settings → Privacy & Security → Microphone**.
2. **Speech Recognition**: Grant when prompted or in **System Settings → Privacy & Security → Speech Recognition**.
3. **Accessibility**: Click **"Open Settings"** next to Accessibility, unlock settings, and toggle **ScreenSense** (or your terminal application if running via `swift run`) ON in **System Settings → Privacy & Security → Accessibility**.

---

## 4. Manual Testing Checklist

### Test Case 1: Primary Paste Flow in External App
1. Open **TextEdit** (or any text editor).
2. Type some text, e.g., `Hello from ScreenSense!`.
3. Select and copy it (`⌘C`).
4. Move your cursor to a blank line.
5. Press the ScreenSense global shortcut: **`⌥ ⇧ Space`** (Option + Shift + Space).
6. Listen for the start audio cue (`Tink`) and see the menu bar icon turn red (🔴).
7. Speak clearly: **`paste`** (or `please paste`, `paste here`).
8. **Verification**:
   - Audio feedback (`Glass`) plays.
   - ScreenSense synthesizes `⌘V`.
   - The clipboard contents appear at the active cursor in TextEdit.

### Test Case 2: Global Shortcut from Another Active App
1. Focus Safari, Terminal, or Slack.
2. Ensure ScreenSense is running in the background.
3. Place cursor in an input box or text field.
4. Press **`⌥ ⇧ Space`** and say **`paste here`**.
5. **Verification**: ScreenSense triggers, parses the command, and pastes the text directly into the active field without switching focus away.

### Test Case 3: Unsupported Command Handling
1. Press **`⌥ ⇧ Space`**.
2. Say: **`open browser`**.
3. **Verification**:
   - ScreenSense acknowledges transcript `"open browser"`.
   - Error sound (`Basso`) plays.
   - Menu bar status shows: `Error: Command not recognized: "open browser"`.
   - No keystrokes are simulated.

---

## 5. Automated Test Suite

Run the full automated test suite:
```bash
swift test
```

### Test Coverage Summary:
- **`CommandParserTests`**:
  - `testStringNormalization`: Punctuation stripping, lowercase normalization, whitespace trimming.
  - `testPasteCommandParsing`: Exact matches (`"paste"`, `"Paste"`, `"PASTE"`).
  - `testPasteVariationsParsing`: Natural language variations (`"paste here"`, `"please paste"`, `"paste this"`, `"screensense paste"`).
  - `testEmptyTranscript`: Handling empty strings and silence.
  - `testUnsupportedCommands`: Verification that unrecognized intents reject safely.
- **`PasteManagerTests`**:
  - `testPasteManagerSuccess`: Mocked `InputSimulatorProtocol` verifying `⌘V` trigger.
  - `testPasteManagerErrorPropagation`: Graceful handling of missing Accessibility permissions.
  - `testPasteCommandExecutionThroughContext`: End-to-end command context execution.
- **`CoordinatorTests`**:
  - `testCoordinatorStartAndHotkeyTrigger`: Global hotkey registration & trigger dispatch.
  - `testCoordinatorVoiceToPasteExecutionFlow`: Full simulated voice → transcript → command → paste flow.
  - `testCoordinatorUnsupportedCommandFlow`: Safe failure state on unsupported voice input.
  - `testCoordinatorMissingPermissionsBlocked`: Safety block when permissions are not granted.

---

## 6. Known Limitations (Phase 1 Scope)

- Only deterministic commands are supported (e.g., `paste`, `paste here`, `please paste`).
- Advanced commands requiring visual context or LLMs (e.g., "click the submit button", "summarize this page") are deferred to later phases.
- If Accessibility permission is revoked by the OS, `⌘V` synthesis fails with an explicit error prompt instructing the user to grant permission.

---

## 7. Recommended Next Steps for Phase 2

1. **Multimodal Screen Perception**: Add screen snapshot capture (`CGDisplayStream` / `ScreenCaptureKit`) when the hotkey is triggered.
2. **Pluggable Local Whisper Engine**: Integrate `whisper.cpp` / CoreML Whisper as an alternative implementation of `SpeechRecognizerProtocol` for completely offline speech recognition.
3. **Context-Aware Commands**: Introduce `CopyCommand`, `SelectCommand`, and OCR text extraction.
