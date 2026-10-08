import Foundation

public final class VoiceManager: VoiceManagerProtocol, @unchecked Sendable {
    private let speechRecognizer: SpeechRecognizerProtocol
    private let audioFeedback: AudioFeedbackProtocol
    private var silenceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.screensense.voicemanager")
    private var lastKnownTranscript = ""
    private var completionHandler: (@Sendable (Result<String, Error>) -> Void)?

    public var isListening: Bool {
        speechRecognizer.isRecording
    }

    public init(
        speechRecognizer: SpeechRecognizerProtocol = AppleSpeechRecognizer(),
        audioFeedback: AudioFeedbackProtocol = SystemAudioFeedback()
    ) {
        self.speechRecognizer = speechRecognizer
        self.audioFeedback = audioFeedback
    }

    public func startListening(
        onPartialTranscript: @escaping @Sendable (String) -> Void,
        onCompletion: @escaping @Sendable (Result<String, Error>) -> Void
    ) throws {
        queue.sync {
            lastKnownTranscript = ""
            completionHandler = onCompletion
            audioFeedback.playSound(.startListening)
        }

        try speechRecognizer.startRecognition(
            onPartialResult: { [weak self] partial in
                guard let self = self else { return }
                self.queue.async {
                    self.lastKnownTranscript = partial
                    self.resetSilenceTimer()
                }
                onPartialTranscript(partial)
            },
            onFinalResult: { [weak self] result in
                guard let self = self else { return }
                self.queue.async {
                    self.cancelSilenceTimer()
                    self.audioFeedback.playSound(.stopListening)
                    self.completionHandler?(result)
                    self.completionHandler = nil
                }
            }
        )

        // Set maximum listening timeout (e.g. 5 seconds) in case no speech occurs
        queue.async {
            self.scheduleMaxDurationTimeout()
        }
    }

    public func stopListening() {
        queue.async {
            self.cancelSilenceTimer()
            if self.speechRecognizer.isRecording {
                self.speechRecognizer.stopRecognition()
                self.audioFeedback.playSound(.stopListening)

                let finalTranscript = self.lastKnownTranscript
                self.completionHandler?(.success(finalTranscript))
                self.completionHandler = nil
            }
        }
    }

    private func resetSilenceTimer() {
        cancelSilenceTimer()

        // Wait 1.0 seconds after user stops speaking before auto-completing
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(1000))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            ScreenSenseLogger.voice.info("Silence detected, completing voice capture with '\(self.lastKnownTranscript, privacy: .public)'")
            self.stopListening()
        }
        timer.resume()
        self.silenceTimer = timer
    }

    private func scheduleMaxDurationTimeout() {
        // Fallback max duration timer (5 seconds)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.speechRecognizer.isRecording {
                ScreenSenseLogger.voice.info("Max voice capture duration reached")
                self.stopListening()
            }
        }
        timer.resume()
        self.silenceTimer = timer
    }

    private func cancelSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }
}
