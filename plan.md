# ScreenSense: Phase 1 Architecture & Implementation Plan

## 1. Executive Summary

ScreenSense is a macOS-native voice-controlled screen interaction assistant. Phase 1 establishes the core foundation: listening for global hotkeys, capturing speech, deterministically parsing voice commands, and executing `⌘V` (paste) into the currently active macOS application.

---

## 2. Architecture & Modular Structure

ScreenSense is built with a modular, protocol-driven architecture to ensure zero tight-coupling and seamless extensibility for subsequent phases (such as multimodal screen context, LLM reasoning, or custom speech recognition engines).

```text
ScreenSense/
├── Package.swift               # SPM configuration defining ScreenSenseCore, ScreenSenseApp & Tests
├── Resources/
│   └── Info.plist              # Bundle metadata and TCC usage descriptions
├── scripts/
│   └── build_app.sh            # Bundling and signing automation (.app)
├── Sources/
│   ├── ScreenSenseCore/        # Core business logic and hardware abstractions
│   │   ├── Core/
│   │   │   ├── Models/         # ScreenSenseState, PermissionStatus
│   │   │   ├── Protocols/      # Hotkey, Voice, Parser, Input, Clipboard, Permission protocols
│   │   │   ├── Utilities/      # Logger (os.Logger), StringNormalizer, SoundFeedback
│   │   │   └── ScreenSenseCoordinator.swift # Central orchestrator & state machine
│   │   ├── Hotkey/             # Carbon-based global hotkey manager
│   │   ├── Voice/              # AppleSpeechRecognizer (SFSpeechRecognizer + AVAudioEngine) & VoiceManager
│   │   ├── Commands/           # Deterministic parser and Command protocols (PasteCommand)
│   │   ├── Clipboard/          # SystemClipboardManager (safe read-only inspection)
│   │   ├── Input/              # CGEventInputSimulator & PasteManager (⌘V synthesis)
│   │   └── Permissions/        # PermissionManager (Microphone, Speech Recognition, Accessibility)
│   └── ScreenSenseApp/         # Executable Target
│       ├── App/                # ScreenSenseApp (@main SwiftUI App) & AppDelegate
│       └── UI/                 # MenuBarView (SwiftUI status item popover & controls)
└── Tests/
    └── ScreenSenseTests/       # Unit & Integration Tests (12 tests)
        ├── CommandParserTests.swift
        ├── PasteManagerTests.swift
        └── CoordinatorTests.swift
```

---

## 3. Core Components & Responsibilities

| Component | Protocol | Responsibility |
| :--- | :--- | :--- |
| **`CarbonHotkeyManager`** | `HotkeyManagerProtocol` | Registers and handles system-wide global shortcut (`⌥⇧Space`) via Carbon Event HotKey APIs without polling. |
| **`AppleSpeechRecognizer`** | `SpeechRecognizerProtocol` | Streams microphone audio via `AVAudioEngine` and transcodes speech to text via `SFSpeechRecognizer`. Pluggable for Whisper / local STT in future phases. |
| **`VoiceManager`** | `VoiceManagerProtocol` | Orchestrates voice recording session lifecycle, audio feedback cues, and silence detection. |
| **`DeterministicCommandParser`** | `CommandParserProtocol` | Normalizes spoken transcripts and matches command intents (e.g. `"paste"`, `"paste here"`, `"please paste"`) to structured `Command` objects. |
| **`PasteManager`** | `PasteManagerProtocol` | High-level paste coordinator. |
| **`CGEventInputSimulator`** | `InputSimulatorProtocol` | Emits native `⌘V` (`kVK_ANSI_V` with `.maskCommand`) key press/release events to the active focused application via `CGEvent`. |
| **`SystemClipboardManager`** | `ClipboardManagerProtocol` | Safe clipboard inspection without mutating or logging sensitive contents. |
| **`PermissionManager`** | `PermissionManagerProtocol` | Checks and triggers prompts for Microphone, Speech Recognition, and macOS Accessibility permissions. |
| **`ScreenSenseCoordinator`** | `@MainActor ObservableObject` | Central coordinator wiring hotkeys, voice, parsing, input execution, and UI state notifications. |

---

## 4. Design Decisions & Rationale

1. **Protocol-First Design for Pluggability**:
   - Every major system is decoupled behind a Swift `protocol`. The speech recognizer (`SpeechRecognizerProtocol`) can be swapped for a local Whisper model in Phase 2 without changing the voice manager or parser.
2. **Native Carbon Hotkeys**:
   - Uses Carbon's `RegisterEventHotKey` for lightweight, event-driven global shortcuts that work across all applications without requiring Accessibility event tap interception or polling.
3. **Deterministic Command Parsing (Phase 1)**:
   - For Phase 1, an LLM is intentionally omitted. A deterministic parser handles variations like *"paste"*, *"paste here"*, *"please paste"*, *"paste this"*, and ignores conversational filler words.
4. **Focused Native Paste Execution**:
   - `PasteCommand` synthesizes `⌘V` using `CGEvent.post(tap: .cghidEventTap)` to send the standard paste shortcut to whatever window or input field currently has keyboard focus.
5. **Swift Concurrency & Thread Safety**:
   - Full Swift 6 strict concurrency compliance (`Sendable` annotations, `@MainActor` state management, actor-safe closures).

---

## 5. Permissions Architecture

ScreenSense requires three macOS permissions:
1. **Microphone (`NSMicrophoneUsageDescription`)**: Required by `AVAudioEngine` to capture user voice.
2. **Speech Recognition (`NSSpeechRecognitionUsageDescription`)**: Required by `SFSpeechRecognizer` to convert audio buffers to transcripts.
3. **Accessibility**: Required by `CGEvent.post` to synthesize `⌘V` keystrokes to external focused applications.

The UI provides instant visual badges for each permission status and one-click actions to open the specific System Settings pane.

---

## 6. How Phase 1 Fits into the Future Architecture

Phase 1 provides the sensory (voice/hotkey) and motor (keystroke/paste) foundation. In later phases:
- **Phase 2 (Multimodal / Screen Context)**: Add screen capture and OCR/accessibility tree extraction into the `CommandExecutionContext`.
- **Phase 3 (LLM & Complex Intents)**: Swap or augment `CommandParserProtocol` with an LLM-based intent resolver (`Copy`, `Select`, `Explain`, `Find`, `Fill Form`).
- **Phase 4 (Local Offline STT)**: Add `WhisperSpeechRecognizer` implementing `SpeechRecognizerProtocol`.
