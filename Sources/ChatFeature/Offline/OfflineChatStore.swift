import CryptoKit
import Foundation
import Models

/// The chat list as last read from a computer, kept for reading offline.
public struct CachedChatList: Codable, Equatable, Sendable {
    public let version: Int
    public let savedAt: Date
    public let chats: [ChatSummary]
    public let favorites: [ChatSummary]
}

/// One opened chat's newest page as last read from a computer.
struct CachedChatPage: Codable, Sendable {
    let version: Int
    let savedAt: Date
    let page: ChatHistoryPage
}

/// A per-computer, on-disk copy of the chat list and the chats opened last (read-only offline mode).
/// Layout: `<root>/<sha256(fingerprint)>/list.json` and `chats/<chatId>.json`.
public struct OfflineChatStore: Sendable {
    public static let maxChats = 50
    static let currentVersion = 1

    let folder: URL
    /// The computer this store belongs to; a writer checks it still is the active one (M1).
    public let fingerprint: String

    public init(root: URL, fingerprint: String) {
        self.fingerprint = fingerprint
        folder = root.appending(path: Self.folderName(fingerprint), directoryHint: .isDirectory)
    }

    public static var standardRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OfflineChats", directoryHint: .isDirectory)
    }

    public static func standard(fingerprint: String) -> OfflineChatStore {
        OfflineChatStore(root: standardRoot, fingerprint: fingerprint)
    }

    static func folderName(_ fingerprint: String) -> String {
        SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var listURL: URL { folder.appending(path: "list.json") }
    var chatsFolder: URL { folder.appending(path: "chats", directoryHint: .isDirectory) }

    private func pageURL(_ chatId: String) -> URL? {
        guard UUID(uuidString: chatId) != nil else { return nil }
        return chatsFolder.appending(path: "\(chatId).json")
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func saveList(chats: [ChatSummary], favorites: [ChatSummary], at date: Date) {
        let list = CachedChatList(version: Self.currentVersion, savedAt: date, chats: chats, favorites: favorites)
        write(list, to: listURL)
    }

    public func loadList() -> CachedChatList? {
        guard let list: CachedChatList = read(listURL), list.version == Self.currentVersion else { return nil }
        return list
    }

    func savePage(_ page: ChatHistoryPage, chatId: String, at date: Date) {
        guard let url = pageURL(chatId) else { return }
        write(CachedChatPage(version: Self.currentVersion, savedAt: date, page: page), to: url)
        // Eviction orders by modification date, so it is the save date and needs no decoding.
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        evict()
    }

    func loadPage(chatId: String) -> CachedChatPage? {
        guard let url = pageURL(chatId), let cached: CachedChatPage = read(url),
            cached.version == Self.currentVersion
        else { return nil }
        return cached
    }

    public func cachedChatIds() -> Set<String> {
        Set(pageFiles().map { $0.deletingPathExtension().lastPathComponent })
    }

    public func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes the folders of computers no longer paired.
    public static func prune(root: URL, keeping fingerprints: Set<String>) {
        let keep = Set(fingerprints.map(folderName))
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in folders where !keep.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Disk

    private func pageFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: chatsFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
    }

    /// Keeps the `maxChats` newest pages by modification date (every save sets it to `savedAt`), without decoding
    /// any of them. A file with no readable date is deleted.
    private func evict() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: chatsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let pages = files.filter { $0.pathExtension == "json" }
        guard pages.count > Self.maxChats else { return }
        var dated: [(url: URL, date: Date)] = []
        for url in pages {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                dated.append((url, date))
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard dated.count > Self.maxChats else { return }
        dated.sort { $0.date > $1.date }
        for entry in dated.dropFirst(Self.maxChats) { try? FileManager.default.removeItem(at: entry.url) }
    }

    private func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let fm = FileManager.default
        guard let data = try? Self.encoder().encode(value),
            (try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
            (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil
        else { return }
        var folder = self.folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }
}
