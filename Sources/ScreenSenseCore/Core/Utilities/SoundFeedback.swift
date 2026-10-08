import Foundation
import AppKit

public enum FeedbackSoundType: Sendable {
    case startListening
    case stopListening
    case success
    case failure
}

public protocol AudioFeedbackProtocol: Sendable {
    func playSound(_ type: FeedbackSoundType)
}

public final class SystemAudioFeedback: AudioFeedbackProtocol, @unchecked Sendable {
    public init() {}

    public func playSound(_ type: FeedbackSoundType) {
        DispatchQueue.main.async {
            switch type {
            case .startListening:
                NSSound(named: "Tink")?.play()
            case .stopListening:
                NSSound(named: "Pop")?.play()
            case .success:
                NSSound(named: "Glass")?.play()
            case .failure:
                NSSound(named: "Basso")?.play()
            }
        }
    }
}
