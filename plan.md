# ScreenSense: Architecture & Implementation Plan

## 1. Executive Summary

ScreenSense is a macOS-native voice-controlled screen interaction assistant.
- **Phase 1** established the core application foundation: listening for global hotkeys, capturing speech, deterministically parsing voice commands, and executing `⌘V` (paste) into the currently active macOS application.
- **Phase 2 (Screen Context Engine)** enables ScreenSense to answer: **"What content is currently visible to the user?"** via dual-channel acquisition: **Chrome Browser DOM** and native **macOS ScreenCaptureKit**, unified through a common `VisibleContext` model.

---

## 2. Architecture & Modular Structure

ScreenSense is built with a modular, protocol-driven architecture with zero tight coupling between sensory acquisition, platform bridges, and command processing.

```text
ScreenSense/
├── Package.swift               # SPM configuration defining ScreenSenseCore, ScreenSenseApp & Tests
├── Resources/
│   └── Info.plist              # Bundle metadata and TCC usage descriptions
├── scripts/
│   └── build_app.sh            # Bundling and signing automation (.app)
├── Extension/                  # Chrome Extension (Manifest V3)
│   ├── manifest.json           # Extension permissions and background worker registration
│   ├── icons/                  # 16px, 48px, 128px PNG icons
│   ├── content/
│   │   ├── visibility-analyzer.js # Precise viewport intersection and visibility percentage
│   │   ├── dom-analyzer.js        # DOM traversal, semantic mapping, reading order sorting
│   │   └── content.js             # Message dispatcher & local HTTP bridge sync
│   ├── background/
│   │   └── service-worker.js      # Active tab coordinator
│   └── popup/
│       ├── popup.html             # Extension connection and viewport element inspector
│       └── popup.js               # Manual sync trigger & bridge status checker
├── TestPage/
│   └── index.html              # Comprehensive test page (10+ paragraphs, hidden nodes, live HUD)
├── Sources/
│   ├── ScreenSenseCore/        # Core business logic and hardware abstractions
│   │   ├── Core/
│   │   │   ├── Models/         # ScreenSenseState, PermissionStatus
│   │   │   ├── Protocols/      # Hotkey, Voice, Parser, Input, Context, Bridge protocols
│   │   │   ├── Utilities/      # Logger (os.Logger), StringNormalizer, SoundFeedback
│   │   │   └── ScreenSenseCoordinator.swift # Central orchestrator & state machine
│   │   ├── Context/            # Phase 2 Context Engine
│   │   │   ├── Models/         # VisibleContext, VisibleElement, ElementBounds, ViewportInfo
│   │   │   ├── DOMContextProvider.swift # DOM context provider via browser bridge
│   │   │   └── ContextFusion.swift      # Context fusion layer (DOM + ScreenCaptureKit)
│   │   ├── ScreenCapture/      # ScreenCaptureKit integration
│   │   │   ├── ScreenCaptureResult.swift
│   │   │   └── SCKScreenCaptureProvider.swift # Native on-demand screen capture
│   │   ├── BrowserBridge/      # Local HTTP bridge for Chrome Extension (127.0.0.1:41920)
│   │   │   └── LocalBrowserBridge.swift
│   │   ├── Hotkey/             # Carbon-based global hotkey manager (⌥⇧Space)
│   │   ├── Voice/              # AppleSpeechRecognizer (SFSpeechRecognizer + AVAudioEngine)
│   │   ├── Commands/           # Deterministic parser and Command protocols (PasteCommand)
│   │   ├── Clipboard/          # SystemClipboardManager (safe read-only inspection)
│   │   ├── Input/              # CGEventInputSimulator & PasteManager (⌘V synthesis)
│   │   └── Permissions/        # PermissionManager (Mic, Speech, Accessibility, Screen Recording)
│   └── ScreenSenseApp/         # Executable Target
│       ├── App/                # ScreenSenseApp (@main SwiftUI App) & AppDelegate
│       └── UI/                 # MenuBarView (Voice Controls + Screen Context Developer Debug View)
└── Tests/
    └── ScreenSenseTests/       # 20 Unit & Integration Tests
        ├── CommandParserTests.swift
        ├── PasteManagerTests.swift
        ├── CoordinatorTests.swift
        ├── ContextModelTests.swift
        ├── ContextFusionTests.swift
        └── LocalBrowserBridgeTests.swift
```

---

## 3. Core Components & Responsibilities

| Component | Protocol | Responsibility |
| :--- | :--- | :--- |
| **`SCKScreenCaptureProvider`** | `ScreenCaptureProviderProtocol` | On-demand single-frame capture via Apple's `ScreenCaptureKit` (`SCScreenshotManager`). Captures active display/window without continuous recording. |
| **`LocalBrowserBridge`** | `BrowserBridgeProtocol` | Lightweight offline HTTP bridge on `127.0.0.1:41920` receiving `VisibleContext` payloads from the Chrome extension with full CORS support. |
| **`DOMContextProvider`** | `DOMContextProviderProtocol` | Provides high-fidelity semantic DOM context extracted from the active browser tab. |
| **`ContextFusion`** | `ContextFusionProtocol` | Merges structured DOM elements with visual ScreenCaptureKit confirmation into a unified `VisibleContext`. |
| **`VisibilityAnalyzer` (JS)** | Content Script | Calculates element intersection with `[0, 0, innerWidth, innerHeight]`, visibility percentage (`0.0` - `1.0`), and filters hidden nodes. |
| **`DOMAnalyzer` (JS)** | Content Script | Traverses DOM, maps semantic types (`heading`, `paragraph`, `code`, `button`, etc.), eliminates parent/child duplicates, and sorts in top-to-bottom reading order. |
| **`CarbonHotkeyManager`** | `HotkeyManagerProtocol` | Registers and handles system-wide global shortcut (`⌥⇧Space`) via Carbon Event HotKey APIs. |
| **`AppleSpeechRecognizer`** | `SpeechRecognizerProtocol` | Streams microphone audio via `AVAudioEngine` and transcodes speech to text via `SFSpeechRecognizer`. |
| **`DeterministicCommandParser`** | `CommandParserProtocol` | Normalizes spoken transcripts and matches command intents (e.g. `"paste"`, `"paste here"`). |
| **`PasteManager` & `CGEventInputSimulator`** | `PasteManagerProtocol` | Emits native `⌘V` key press/release events to the active focused application via `CGEvent`. |
| **`ScreenSenseCoordinator`** | `@MainActor ObservableObject` | Central coordinator wiring hotkeys, voice, parsing, context acquisition, fusion, and UI state. |

---

## 4. Visible Element Detection Rules

The context engine adheres to the following rules to extract **what is visible in the current viewport**:

1. **Structural Hiddenness (Self & Ancestor)**:
   - Elements with computed `display: none`, `visibility: hidden`, `opacity: 0`, `[hidden]`, `[inert]`, or `[aria-hidden="true"]` are strictly excluded.
   - Elements whose ancestor container has `[aria-hidden="true"]`, `[hidden]`, `[inert]`, `display: none`, `visibility: hidden`, or `opacity: 0` are recursively excluded via `element.closest()` and ancestor tree evaluation.
2. **Zero Dimension Filter**:
   - Elements with `width === 0` or `height === 0` are excluded.
3. **Viewport Intersection Geometry**:
   - `visibleWidth = max(0, min(viewportWidth, rect.right) - max(0, rect.left))`
   - `visibleHeight = max(0, min(viewportHeight, rect.bottom) - max(0, rect.top))`
   - `visibleArea = visibleWidth * visibleHeight`
   - `visibilityPercentage = visibleArea / (rect.width * rect.height)`
   - Elements scrolled above or below the viewport (`visibleArea <= 0` or `visibilityPercentage < 0.02`) are filtered out.
4. **Spatial Reading Order**:
   - Elements are sorted primarily by vertical position (`bounds.y` ascending), secondary by horizontal position (`bounds.x` ascending).
5. **Deduplication of Nested Containers**:
   - Parent containers (`<article>`, `<section>`, `<div>`) whose text content is entirely composed of child paragraphs/headings are skipped to avoid duplicate textual nodes.

---

## 5. Context Fusion Architecture

```text
[ Chrome Extension Content Script ]
               │
               ▼ (POST /api/context on 127.0.0.1:41920)
       [ LocalBrowserBridge ] ──► [ DOMContextProvider ]
                                             │
[ SCKScreenCaptureProvider ] ────────────────┼──► [ ContextFusion ] ──► [ Unified VisibleContext ]
 (ScreenCaptureKit On-Demand)                │                                 │
                                                                               ▼
                                                                  [ ScreenSenseCoordinator ]
                                                                               │
                                                                  [ MenuBar Developer View ]
```

- **When DOM context is available**: The unified context uses exact semantic DOM elements, spatial bounding rects, and attaches the ScreenCaptureKit visual screenshot as confirmation.
- **When DOM is unavailable (e.g. non-browser application)**: ScreenCaptureKit provides visual context with display resolution and window metadata, establishing the fallback foundation for Phase 3 OCR/Vision.

---

## 6. Permissions Architecture

1. **Microphone (`NSMicrophoneUsageDescription`)**: Required by `AVAudioEngine` for voice input.
2. **Speech Recognition (`NSSpeechRecognitionUsageDescription`)**: Required by `SFSpeechRecognizer` for speech-to-text.
3. **Accessibility**: Required by `CGEvent.post` to synthesize `⌘V` keystrokes.
4. **Screen Recording**: Required by `ScreenCaptureKit` (`SCScreenshotManager`) for visual screen context capture.

---

## 7. Roadmap & Phase Progression

- **Phase 1 (Complete)**: macOS application foundation, global hotkey, voice recognition, command parser, paste execution.
- **Phase 2 (Complete)**: Screen Context Engine, Chrome Extension DOM viewport extraction, ScreenCaptureKit on-demand capture, Context Fusion, developer debug UI.
- **Phase 3 (Next)**: Local OCR / Vision engine, Multimodal LLM reasoning, context-aware commands (`Copy`, `Select`, `Explain`, `Find`).
