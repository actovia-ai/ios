import Foundation
import MarkdownKit
import Models
import NetworkingKit
import UIKit

/// Where one generated image's pixels come from, settled when the card is built.
enum GeneratedImageSource: Equatable, Hashable, Sendable {
    /// A file the desktop saved and serves at `/api/v1/media/<chatId>/<mediaId>`, fetched with the device's token.
    case media(path: String)

    /// The route's path, or nil when an id is not the plain shape the desktop writes (so nothing odd reaches the
    /// path). A Philharmonic image has no `chatId` and is not served.
    static func mediaPath(chatId: String?, mediaId: String) -> String? {
        guard let chatId, chatId.wholeMatch(of: /[0-9A-Za-z-]{1,64}/) != nil,
            mediaId.wholeMatch(of: /[0-9A-Za-z-]{1,64}\.(png|jpe?g|webp)/) != nil
        else { return nil }
        return "/api/v1/media/\(chatId)/\(mediaId)"
    }

    init?(_ image: GeneratedImage) {
        guard let mediaId = image.mediaId, let path = Self.mediaPath(chatId: image.chatId, mediaId: mediaId) else {
            return nil
        }
        self = .media(path: path)
    }

    var cacheKey: String {
        switch self {
        case .media(let path): "media:\(path)"
        }
    }
}

/// An `image_generation` call as its card draws it, from the moment it is made: running, finished (one frame per
/// image) or failed. Built once in `ToolCard.init`.
struct ImageGenerationCardModel: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case generating
        case complete
        case failed(message: String?)
    }

    struct Frame: Equatable, Sendable, Identifiable {
        let id: Int
        /// Nil: the row names no file this phone can fetch (a Group image, an id of the wrong shape).
        let source: GeneratedImageSource?
        let revisedPrompt: String?
        /// Width over height.
        let aspectRatio: Double
    }

    let prompt: String
    let status: Status
    let frames: [Frame]
    /// The size the call asked for, as a badge (`1024 × 1536`); nil for `auto`.
    let resolution: String?

    static func running(arguments: JSONValue?) -> ImageGenerationCardModel {
        ImageGenerationCardModel(
            prompt: prompt(arguments), status: .generating, frames: [Frame(id: 0, source: nil, revisedPrompt: nil, aspectRatio: 1)],
            resolution: nil)
    }

    static func failed(arguments: JSONValue?, message: String?) -> ImageGenerationCardModel {
        ImageGenerationCardModel(
            prompt: prompt(arguments), status: .failed(message: message),
            frames: [Frame(id: 0, source: nil, revisedPrompt: nil, aspectRatio: 1)], resolution: nil)
    }

    init(_ call: DecodedCall<ImageGenerationArguments, ImageGenerationResult>) {
        let size = Self.parseSize(call.result.size)
        prompt = call.arguments?.prompt ?? ""
        status = .complete
        resolution = size.map { "\($0.width) × \($0.height)" }
        let fallback = size.map { Double($0.width) / Double($0.height) } ?? 1
        let frames = call.result.images.enumerated().map { index, image in
            let own = image.width.flatMap { width in image.height.map { Double(width) / Double($0) } }
            return Frame(
                id: index, source: GeneratedImageSource(image), revisedPrompt: image.revisedPrompt,
                aspectRatio: own ?? fallback)
        }
        self.frames = frames.isEmpty ? [Frame(id: 0, source: nil, revisedPrompt: nil, aspectRatio: fallback)] : frames
    }

    private init(prompt: String, status: Status, frames: [Frame], resolution: String?) {
        self.prompt = prompt
        self.status = status
        self.frames = frames
        self.resolution = resolution
    }

    /// `1024x1536` → its two sides; `auto`, empty or anything else → nil (a square, no badge), as on the desktop.
    static func parseSize(_ size: String?) -> (width: Int, height: Int)? {
        guard let size, let match = size.wholeMatch(of: /(\d{1,5})x(\d{1,5})/), let width = Int(match.1),
            let height = Int(match.2), width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    private static func prompt(_ arguments: JSONValue?) -> String {
        if case .object(let object)? = arguments { object["prompt"]?.stringValue ?? "" } else { "" }
    }
}

/// How far one frame has got, as the card shows it: the desktop's statuses plus the phone's own (a load that can be
/// retried).
enum ImageFrameStatus: Equatable, Sendable {
    case generating
    /// Finished on the computer; its bytes are on their way.
    case refining
    case complete
    case error
    case unavailable
    case loadFailed

    var isActive: Bool { self == .generating || self == .refining }
}

/// Where one frame's image load stands.
enum GeneratedImageLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(GeneratedImageLoader.Failure)
}

enum ImageGenerationRules {
    /// A call still pending in a turn that is no longer streaming was stopped: it will never produce an image.
    static func frameStatus(
        card: ImageGenerationCardModel.Status, isLive: Bool, source: GeneratedImageSource?,
        load: GeneratedImageLoadState
    ) -> ImageFrameStatus {
        switch card {
        case .generating: return isLive ? .generating : .unavailable
        case .failed: return .error
        case .complete: break
        }
        guard source != nil else { return .unavailable }
        switch load {
        case .loaded: return .complete
        case .failed(.failed): return .loadFailed
        case .failed: return .unavailable
        case .idle, .loading: return .refining
        }
    }
}

/// Generated images kept in memory only (the session is ephemeral, nothing goes to disk), shared by every chat.
final class GeneratedImageCache: @unchecked Sendable {
    static let shared = GeneratedImageCache()
    private let storage = NSCache<NSString, UIImage>()

    /// About fifteen of the desktop's 1536 × 1024 images; the frame's own image stands in for an evicted one.
    init(totalCostLimit: Int = 96 * 1024 * 1024) {
        storage.totalCostLimit = totalCostLimit
    }

    func image(for source: GeneratedImageSource) -> UIImage? { storage.object(forKey: source.cacheKey as NSString) }

    func removeAll() { storage.removeAllObjects() }

    func insert(_ image: UIImage, for source: GeneratedImageSource) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        storage.setObject(image, forKey: source.cacheKey as NSString, cost: Int(pixels) * 4)
    }
}

/// Fetches a generated image from the desktop's media route through the paired session (token, pinned TLS).
final class GeneratedImageLoader: Sendable {
    enum Failure: Error, Equatable, Sendable {
        /// Gone for good: 404/400 (the chat was deleted, a reset), bytes that are no image.
        case unavailable
        /// The computer refused this device's token (it was revoked; the app returns to pairing).
        case unauthorized
        /// Anything else (no connection, a timeout, a 5xx): worth a retry.
        case failed
    }

    typealias Fetch = @Sendable (String) async throws -> Data

    private let fetchMedia: Fetch
    let cache: GeneratedImageCache

    init(fetchMedia: @escaping Fetch, cache: GeneratedImageCache = .shared) {
        self.fetchMedia = fetchMedia
        self.cache = cache
    }

    convenience init(apiClient: APIClient, cache: GeneratedImageCache = .shared) {
        self.init(fetchMedia: { try await apiClient.data($0) }, cache: cache)
    }

    func cached(_ source: GeneratedImageSource) -> UIImage? { cache.image(for: source) }

    /// The image, from the cache when it is there. Throws a `Failure`, or `CancellationError`.
    func load(_ source: GeneratedImageSource) async throws -> UIImage {
        if let hit = cache.image(for: source) { return hit }
        let data: Data
        do {
            switch source {
            case .media(let path): data = try await fetchMedia(path)
            }
        } catch {
            throw try Self.failure(for: error)
        }
        try Task.checkCancellation()
        let image = try await Self.decode(data)
        let prepared = await image.byPreparingForDisplay() ?? image
        cache.insert(prepared, for: source)
        return prepared
    }

    /// The longest side an image is decoded at: above what the desktop generates (1536), so its images keep every
    /// pixel, while a tampered file (a 20k × 20k PNG) is never decoded at full size.
    static let maxPixelSize = 2048

    /// Downsampled through the markdown's decoder, off the main actor; bytes that are no image are unavailable.
    @concurrent
    nonisolated static func decode(_ data: Data) async throws -> UIImage {
        guard let loaded = try? MarkdownImageLoader.downsample(data, maxPixelWidth: maxPixelSize) else {
            throw Failure.unavailable
        }
        return UIImage(cgImage: loaded.cgImage)
    }

    /// What a failed fetch means for the card. Rethrows cancellation.
    static func failure(for error: any Error) throws -> Failure {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
        if let failure = error as? Failure { return failure }
        if let http = error as? HTTPError {
            switch http.statusCode {
            case 401: return .unauthorized
            case 400, 404, 410: return .unavailable
            default: return .failed
            }
        }
        return .failed
    }
}
