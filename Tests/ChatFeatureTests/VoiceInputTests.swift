import Foundation
import NetworkingKit
import Testing

@testable import ChatFeature

@Suite("Transcriber: the recording's upload and the computer's answer")
struct TranscriberTests {
    private func config() -> ServerConfigStore {
        let suite = "TranscriberTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        config.manualBaseURLString = "http://localhost:60223"
        return config
    }

    @Test("one multipart file field named audio, voice.m4a as audio/mp4, POSTed to the transcription route")
    func request() throws {
        let audio = Data([0x00, 0x01, 0xFE, 0xFF, 0x41])
        let request = try #require(
            Transcriber.request(audio: audio, serverConfig: config(), boundary: "B0UNDARY"))
        #expect(request.url?.path == "/api/v1/audio/transcriptions")
        #expect(request.url?.host == "localhost")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B0UNDARY")
        let body = try #require(request.httpBody)
        let head = Data(
            "--B0UNDARY\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"voice.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n"
                .utf8)
        #expect(body == head + audio + Data("\r\n--B0UNDARY--\r\n".utf8))
    }

    @Test("the paired computer's address and Authorization, as on a chat turn")
    func authorization() async throws {
        let unpaired = try #require(Transcriber.request(audio: Data([1]), serverConfig: config()))
        #expect(unpaired.value(forHTTPHeaderField: "Authorization") == nil)

        let paired = config()
        let connection = ServerConnection(store: PairedStore())
        try await connection.unlock(reason: "test")
        paired.connection = connection
        let request = try #require(Transcriber.request(audio: Data([1]), serverConfig: paired))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
        #expect(request.url?.absoluteString == "https://10.0.0.2:63129/api/v1/audio/transcriptions")
    }

    @Test("the transcription's text")
    func text() throws {
        #expect(try Transcriber.text(from: Data(#"{"text":"hello","usage":{"seconds":3}}"#.utf8)) == "hello")
    }

    @Test("an answer without text, or not JSON, fails")
    func missingText() {
        #expect(throws: Transcriber.Failure.unreadable) { try Transcriber.text(from: Data(#"{"usage":{}}"#.utf8)) }
        #expect(throws: Transcriber.Failure.unreadable) { try Transcriber.text(from: Data("Bad Gateway".utf8)) }
    }

    @Test("the server's error envelope fails with its own message, shown as it is")
    func errorEnvelope() {
        let body = #"{"type":"error","error":{"code":"VALIDATION_FAILED","message":"Invalid file format."}}"#
        #expect(throws: Transcriber.Failure.server("Invalid file format.")) {
            try Transcriber.text(from: Data(body.utf8))
        }
        #expect(Transcriber.message(for: Transcriber.Failure.server("Invalid file format.")) == "Invalid file format.")
        #expect(!Transcriber.message(for: Transcriber.Failure.unreadable).isEmpty)
    }
}

/// A Keychain stand-in holding one paired computer.
private struct PairedStore: CredentialStoring {
    func load(reason: String) async throws -> PairedServer? {
        PairedServer(hosts: ["10.0.0.2"], port: 63129, fingerprint: "ab", name: "Mac", deviceId: "d", token: "t0ken")
    }
    func save(_ server: PairedServer) throws {}
    func clear() throws {}
    var exists: Bool { true }
}

@Suite("TurnButtonState: what the composer's round button is")
struct TurnButtonStateTests {
    @Test("empty: record; text or pictures: send; a turn in flight: stop")
    func idle() {
        #expect(TurnButtonState.for(text: "", hasPictures: false, inFlight: false, recording: .idle) == .mic)
        #expect(TurnButtonState.for(text: "  \n", hasPictures: false, inFlight: false, recording: .idle) == .mic)
        #expect(TurnButtonState.for(text: "hi", hasPictures: false, inFlight: false, recording: .idle) == .send)
        #expect(TurnButtonState.for(text: "", hasPictures: true, inFlight: false, recording: .idle) == .send)
        #expect(TurnButtonState.for(text: "", hasPictures: false, inFlight: true, recording: .idle) == .stop)
        #expect(TurnButtonState.for(text: "hi", hasPictures: true, inFlight: true, recording: .idle) == .stop)
    }

    @Test("recording and transcribing win, text or not")
    func voice() {
        let since = Date(timeIntervalSince1970: 0)
        for text in ["", "typed before"] {
            #expect(
                TurnButtonState.for(text: text, hasPictures: false, inFlight: false, recording: .recording(since: since))
                    == .recording)
            #expect(
                TurnButtonState.for(text: text, hasPictures: false, inFlight: false, recording: .transcribing)
                    == .transcribing)
        }
    }

    @Test("the meter's level and length")
    func meter() {
        #expect(VoiceRecorder.normalizedLevel(decibels: -160) == 0)
        #expect(VoiceRecorder.normalizedLevel(decibels: -25) == 0.5)
        #expect(VoiceRecorder.normalizedLevel(decibels: 3) == 1)
        let start = Date(timeIntervalSince1970: 1000)
        #expect(VoiceRecorder.elapsed(from: start, to: start) == "0:00")
        #expect(VoiceRecorder.elapsed(from: start, to: start.addingTimeInterval(65.7)) == "1:05")
        #expect(VoiceRecorder.elapsed(from: start, to: start.addingTimeInterval(300)) == "5:00")
    }
}

@MainActor
@Suite("ChatDetailViewModel.appendTranscription: the text joins what is typed")
struct AppendTranscriptionTests {
    private func makeModel() -> ChatDetailViewModel {
        let suite = "AppendTranscriptionTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let session = URLSession(configuration: .ephemeral)
        return ChatDetailViewModel(
            chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
            streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
    }

    @Test("into an empty composer, trimmed")
    func empty() {
        let model = makeModel()
        model.appendTranscription("  Plan my day \n")
        #expect(model.composerText == "Plan my day")
        #expect(model.transcriptionCount == 1)
    }

    @Test("after typed text, one space between")
    func appends() {
        let model = makeModel()
        model.composerText = "Remind me"
        model.appendTranscription(" to call Mum ")
        #expect(model.composerText == "Remind me to call Mum")
        model.composerText = "Remind me "
        model.appendTranscription("tomorrow")
        #expect(model.composerText == "Remind me tomorrow")
    }

    @Test("an empty transcription leaves the text as it was")
    func nothing() {
        let model = makeModel()
        model.composerText = "Typed"
        model.appendTranscription("  \n")
        #expect(model.composerText == "Typed")
        #expect(model.transcriptionCount == 0)
        #expect(model.recording == .idle)
    }

    @Test("cancelling or stopping with no recording under way changes nothing")
    func idleControls() async {
        let model = makeModel()
        model.cancelRecording()
        await model.stopRecordingAndTranscribe()
        #expect(model.recording == .idle)
        #expect(model.notice == nil)
    }
}
