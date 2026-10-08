import Foundation
import Speech
import AVFoundation

public enum SpeechRecognitionError: LocalizedError, Sendable {
    case recognizerUnavailable
    case audioEngineFailed(String)
    case requestCreationFailed
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available for the current locale."
        case .audioEngineFailed(let msg):
            return "Audio Engine failure: \(msg)"
        case .requestCreationFailed:
            return "Unable to create speech recognition request."
        case .notAuthorized:
            return "Speech recognition is not authorized. Please grant permission."
        }
    }
}

/// Native Apple Speech Recognizer implementation of `SpeechRecognizerProtocol`
public final class AppleSpeechRecognizer: SpeechRecognizerProtocol, @unchecked Sendable {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine: AVAudioEngine
    private let lock = NSLock()

    private var _isRecording = false

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRecording
    }

    public init(locale: Locale = Locale.current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.audioEngine = AVAudioEngine()
    }

    public func startRecognition(
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (Result<String, Error>) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            ScreenSenseLogger.recognition.error("SFSpeechRecognizer is unavailable")
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // Cancel previous task if any
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // Stop engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition if supported
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            ScreenSenseLogger.recognition.error("AudioEngine failed to start: \(error.localizedDescription)")
            throw SpeechRecognitionError.audioEngineFailed(error.localizedDescription)
        }

        _isRecording = true
        ScreenSenseLogger.recognition.info("Speech recognition started")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                ScreenSenseLogger.recognition.debug("Transcript update: '\(transcript, privacy: .public)' (isFinal: \(result.isFinal))")

                if result.isFinal {
                    self.cleanupAudio()
                    onFinalResult(.success(transcript))
                } else {
                    onPartialResult(transcript)
                }
            }

            if let error = error {
                ScreenSenseLogger.recognition.error("Recognition task error: \(error.localizedDescription)")
                self.cleanupAudio()
                onFinalResult(.failure(error))
            }
        }
    }

    public func stopRecognition() {
        lock.lock()
        defer { lock.unlock() }

        ScreenSenseLogger.recognition.info("Stopping speech recognition...")
        recognitionRequest?.endAudio()
        cleanupAudio()
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        _isRecording = false
    }
}
