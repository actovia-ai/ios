import Foundation
import Models
import Synchronization
import Testing
import UIKit

@testable import PhilharmonicFeature

@Suite("PhilharmonicHue (desktop lib/hue.ts pickHue)")
struct PhilharmonicHueTests {
    /// Vectors from the desktop's `pickHue` (FNV-1a over `charCodeAt`), computed in Node.
    @Test(
        "picks the desktop's hue for the same seed",
        arguments: [
            ("default", PhilharmonicHue.periwinkle), ("Iris", .periwinkle), ("Oskar", .sage),
            ("k3j9x2abq1", .honey), ("11111111-1111-4111-8111-111111111111", .sky), ("设计", .lilac),
            ("🎻x", .lilac),
        ])
    func vectors(seed: String, hue: PhilharmonicHue) {
        #expect(PhilharmonicHue.pick(seed) == hue)
    }

    @Test("a missing or empty seed reads as \"default\"")
    func fallback() {
        #expect(PhilharmonicHue.pick(nil) == .pick("default"))
        #expect(PhilharmonicHue.pick("") == .pick("default"))
    }
}

@Suite("EmployeeAvatars")
struct EmployeeAvatarsTests {
    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    private let iris = Employee(id: "a1", name: "Iris", avatarSeed: "iris-7k2", avatarStyle: "notionists")

    /// Counts the requests and answers each with `answer`.
    private final class Server: Sendable {
        let calls = Mutex<[String]>([])
        let answer: @Sendable () throws -> Data

        init(answer: @escaping @Sendable () throws -> Data) { self.answer = answer }

        func fetch(seed: String?, style: String?, size: Int) async throws -> Data {
            calls.withLock { $0.append("\(seed ?? "-")|\(style ?? "-")|\(size)") }
            return try answer()
        }

        var count: Int { calls.withLock { $0.count } }
    }

    private func avatars(_ server: Server, directory: URL? = nil) -> EmployeeAvatars {
        EmployeeAvatars(
            fetch: { try await server.fetch(seed: $0, style: $1, size: $2) },
            cache: EmployeeAvatarCache(directory: directory))
    }

    @Test("asks for the employee's seed and style at the one pixel size, then serves it from memory")
    func fetchesOnce() async {
        let server = Server { Self.png }
        let avatars = avatars(server)
        #expect(avatars.cached(iris) == nil)
        #expect(await avatars.load(iris) != nil)
        #expect(avatars.cached(iris) != nil)
        #expect(await avatars.load(iris) != nil)
        #expect(server.calls.withLock { $0 } == ["iris-7k2|notionists|\(EmployeeAvatars.pixelSize)"])
    }

    @Test("a desktop without the route (404) is asked once a session; the initials stay")
    func olderDesktop() async {
        let server = Server { throw HTTPError(statusCode: 404, code: "NOT_FOUND", message: "Not found") }
        let avatars = avatars(server)
        #expect(await avatars.load(iris) == nil)
        #expect(await avatars.load(iris) == nil)
        #expect(server.count == 1)
    }

    @Test("no connection is not remembered: the next appearance asks again")
    func offlineRetries() async {
        let server = Server { throw URLError(.notConnectedToInternet) }
        let avatars = avatars(server)
        #expect(await avatars.load(iris) == nil)
        #expect(await avatars.load(iris) == nil)
        #expect(server.count == 2)
    }

    @Test("many bubbles of one employee share one request")
    func sharesInFlight() async {
        let server = Server {
            Thread.sleep(forTimeInterval: 0.05)
            return Self.png
        }
        let avatars = avatars(server)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = await avatars.load(iris) } }
        }
        #expect(server.count == 1)
    }

    @Test("a face kept on disk is drawn offline, by a new session, without asking")
    func diskCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let online = Server { Self.png }
        #expect(await avatars(online, directory: directory).load(iris) != nil)

        let offline = Server { throw URLError(.notConnectedToInternet) }
        #expect(await avatars(offline, directory: directory).load(iris) != nil)
        #expect(offline.count == 0)
    }
}
