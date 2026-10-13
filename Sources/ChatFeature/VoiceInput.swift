import AVFoundation
import Foundation
import NetworkingKit
import Observation

/// Voice input in the composer, as on the desktop (`audio-recorder.tsx`): the phone records, the computer transcribes
/// with the model chosen in its Settings (`POST /api/v1/audio/transcriptions`), and the text joins the composer's.
public enum VoiceRecordingState: Equatable, Sendable {
    case idle
    case recording(since: Date)
    /// The recording is on its way to the computer, or its text on the way back.
    case transcribing
}

/// What the composer's one round button is: it keeps a single identity and morphs between these.
enum TurnButtonState: Equatable {
    case send, stop, mic, recording, transcribing

    /// A recording comes first (nothing else can start while it runs), then a turn in flight; with nothing to send,
    /// the button records.
    static func `for`(text: String, hasPictures: Bool, inFlight: Bool, recording: VoiceRecordingState) -> Self {
        switch recording {
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .idle: break
        }
        if inFlight { return .stop }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || hasPictures ? .send : .mic
    }

    /// The SF Symbol drawn (under the spinner while transcribing, so the button keeps its size).
    var symbol: String {
        switch self {
        case .send, .transcribing: "arrow.up"
        case .stop, .recording: "stop.fill"
        case .mic: "mic.fill"
        }
    }

    /// For UI tests; never shown.
    var identifier: String {
        switch self {
        case .send: "sendButton"
        case .stop: "stopButton"
        case .mic: "micButton"
        case .recording: "stopRecordingButton"
        case .transcribing: "transcribingButton"
        }
    }
}

/// The microphone, through `AVAudioRecorder`: AAC in an `.m4a`, 16 kHz mono at medium quality — speech, small uploads.
/// The audio session is active only while recording, so whatever else was playing resumes afterwards.
@MainActor
@Observable
final class VoiceRecorder {
    /// A recording stops by itself, and is transcribed, after this long.
    nonisolated static let maximumDuration: Duration = .seconds(300)

    @ObservationIgnored private var recorder: AVAudioRecorder?

    /// Whether the microphone may be used, asking the first time.
    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        cancel()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    /// Ends the recording and hands over its bytes (nil: nothing was recorded); the file is removed.
    func stop() -> Data? {
        guard let recorder else { return nil }
        self.recorder = nil
        recorder.stop()
        Self.deactivate()
        defer { try? FileManager.default.removeItem(at: recorder.url) }
        guard let data = try? Data(contentsOf: recorder.url), !data.isEmpty else { return nil }
        return data
    }

    /// Ends the recording and throws it away.
    func cancel() {
        guard let recorder else { return }
        self.recorder = nil
        recorder.stop()
        recorder.deleteRecording()
        Self.deactivate()
    }

    /// The input level now, 0…1, for the meter; 0 when not recording.
    func level() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return Self.normalizedLevel(decibels: Double(recorder.averagePower(forChannel: 0)))
    }

    /// −50 dB (a quiet room) and below is empty, 0 dB full, linear in between.
    nonisolated static func normalizedLevel(decibels: Double) -> Double {
        min(1, max(0, (decibels + 50) / 50))
    }

    /// `m:ss`, as the meter shows the recording's length.
    nonisolated static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60) // l10n:ignore: a time, not words
    }

    private static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The upload: one `multipart/form-data` file field named `audio`, with a real extension — the server sniffs the
/// container by name — answered by OpenAI's transcription object, `{ "text": … }`.
enum Transcriber {
    static let path = "/api/v1/audio/transcriptions"

    enum Failure: Error, Equatable {
        /// The computer's own words (`{ error: { message } }`), shown as they are.
        case server(String)
        /// Anything else: no answer, an answer without text.
        case unreadable
    }

    /// Nil when the server address is not a URL.
    static func request(
        audio: Data, filename: String = "voice.m4a", mimeType: String = "audio/mp4", serverConfig: ServerConfigStore,
        boundary: String = "exodus-\(UUID().uuidString)"
    ) -> URLRequest? {
        guard let base = URL(string: serverConfig.baseURLString) else { return nil }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let authorization = serverConfig.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        // Five minutes of speech uploads in seconds, but the model may take a while to answer.
        request.timeoutInterval = 180
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    /// The transcription's text, or the server's error message as `Failure.server`.
    static func text(from response: Data) throws -> String {
        struct Answer: Decodable {
            struct ServerError: Decodable { let message: String? }
            let text: String?
            let error: ServerError?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response) else { throw Failure.unreadable }
        if let message = answer.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            throw Failure.server(message)
        }
        guard let text = answer.text else { throw Failure.unreadable }
        return text
    }

    /// Sends the recording over the paired computer's pinned session (the plain address's, unpaired); a computer
    /// that answers "locked" is unlocked once and asked again, as a chat turn is.
    static func transcribe(audio: Data, serverConfig: ServerConfigStore) async throws -> String {
        guard let request = request(audio: audio, serverConfig: serverConfig) else { throw Failure.unreadable }
        let session = serverConfig.connection?.session ?? URLSession.shared
        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 423, let connection = serverConfig.connection,
            await connection.unlockComputer(session: session)
        {
            (data, response) = try await session.data(for: request)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let text = try text(from: data)
        guard (200..<300).contains(status) else { throw Failure.unreadable }
        return text
    }

    /// What the notice over the composer says when a transcription failed.
    static func message(for error: Error) -> String {
        if case .server(let message) = error as? Failure { return message }
        return String(
            localized: "ios:chat.composer.transcriptionFailed", defaultValue: "Couldn't transcribe the recording.",
            comment: "Notice over the message field when a voice recording could not be turned into text.")
    }
}
