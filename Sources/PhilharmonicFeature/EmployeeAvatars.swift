import CryptoKit
import Foundation
import Models
import NetworkingKit
import Synchronization
import SwiftUI
import UIKit

/// Employees' faces, fetched from the paired computer: the desktop draws them with DiceBear, which this app has no
/// copy of, and serves the result as a PNG (`PhilharmonicAPI.avatar`). One face is a pure function of the
/// employee's `avatarSeed` and `avatarStyle`, so it is kept for good — in memory and in Caches, where it is there
/// offline too — and asked for once per app session at most.
public struct EmployeeAvatars: Sendable {
    typealias Fetch = @Sendable (_ seed: String?, _ style: String?, _ size: Int) async throws -> Data

    private let fetch: Fetch
    let cache: EmployeeAvatarCache

    init(fetch: @escaping Fetch, cache: EmployeeAvatarCache = .shared) {
        self.fetch = fetch
        self.cache = cache
    }

    public init(api: PhilharmonicAPI) {
        self.init(fetch: { try await api.avatar(seed: $0, style: $1, size: $2) })
    }

    /// The pixel side asked for: a 64 pt avatar at 3×, the largest this app draws. One size, so one file per face.
    static let pixelSize = 192

    /// The face, when it is already in memory: drawn on the first frame, with no placeholder flash.
    func cached(_ employee: Employee) -> UIImage? { cache.memory(EmployeeAvatarKey(employee)) }

    /// The face, or nil when there is none to have: a desktop from before the avatar route (404), or no connection.
    /// A refusal is remembered for the session, so an older desktop is not asked again for every bubble.
    func load(_ employee: Employee) async -> UIImage? {
        let key = EmployeeAvatarKey(employee)
        return await cache.image(for: key) { [fetch] in
            try await fetch(key.seed, key.style, Self.pixelSize)
        }
    }
}

/// What a face is made from.
struct EmployeeAvatarKey: Hashable, Sendable {
    let seed: String?
    let style: String?

    init(seed: String?, style: String?) {
        self.seed = seed
        self.style = style
    }

    init(_ employee: Employee) { self.init(seed: employee.avatarSeed, style: employee.avatarStyle) }

    /// The file it is kept in: a digest, since a seed is any text.
    var fileName: String {
        let text = "\(style ?? "")\u{0}\(seed ?? "\u{0}default")\u{0}\(EmployeeAvatars.pixelSize)"
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
    }
}

/// The faces this session has: decoded images in memory, their PNGs on disk, the keys the computer refused, and the
/// fetches in flight (a transcript shows one employee many times; the first bubble's request serves them all).
final class EmployeeAvatarCache: Sendable {
    static let shared = EmployeeAvatarCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhilharmonicAvatars", isDirectory: true))

    private struct State {
        var images: [EmployeeAvatarKey: UIImage] = [:]
        var refused: Set<EmployeeAvatarKey> = []
        var inFlight: [EmployeeAvatarKey: Task<UIImage?, Never>] = [:]
    }

    private let state = Mutex(State())
    /// nil keeps nothing on disk (tests).
    private let directory: URL?

    init(directory: URL?) {
        self.directory = directory
    }

    func memory(_ key: EmployeeAvatarKey) -> UIImage? { state.withLock { $0.images[key] } }

    func image(for key: EmployeeAvatarKey, fetch: @escaping @Sendable () async throws -> Data) async -> UIImage? {
        let task: Task<UIImage?, Never>? = state.withLock { state in
            if state.images[key] != nil || state.refused.contains(key) { return nil }
            if let running = state.inFlight[key] { return running }
            let task = Task { await self.resolve(key, fetch: fetch) }
            state.inFlight[key] = task
            return task
        }
        guard let task else { return memory(key) }
        return await task.value
    }

    private func resolve(_ key: EmployeeAvatarKey, fetch: @Sendable () async throws -> Data) async -> UIImage? {
        defer { state.withLock { _ = $0.inFlight.removeValue(forKey: key) } }
        if let data = readDisk(key), let image = await Self.decode(data) {
            state.withLock { $0.images[key] = image }
            return image
        }
        do {
            let data = try await fetch()
            guard let image = await Self.decode(data) else {
                state.withLock { _ = $0.refused.insert(key) }
                return nil
            }
            writeDisk(key, data)
            state.withLock { $0.images[key] = image }
            return image
        } catch let error as HTTPError where [400, 404, 405].contains(error.statusCode) {
            // A desktop without the route, or one that will not draw this seed: the initial stays, and it is not
            // asked again this session.
            state.withLock { _ = $0.refused.insert(key) }
            return nil
        } catch {
            // Offline, locked, a timeout: the next appearance tries again.
            return nil
        }
    }

    private func readDisk(_ key: EmployeeAvatarKey) -> Data? {
        guard let directory else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(key.fileName))
    }

    private func writeDisk(_ key: EmployeeAvatarKey, _ data: Data) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
    }

    /// Off the main actor, ready to draw; bytes that are no image are nil.
    @concurrent
    nonisolated static func decode(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }
}

extension EnvironmentValues {
    /// Where employees' faces come from; nil draws initials.
    @Entry public var employeeAvatars: EmployeeAvatars? = nil
}
