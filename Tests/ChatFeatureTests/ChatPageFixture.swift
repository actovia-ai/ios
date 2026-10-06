import Foundation

/// A chat's history as `GET /api/v1/chat/:id/page` answers it (desktop spec 2026-10-01 §C3). The fixtures of these
/// tests are written as the rows of one whole conversation; a mock server answers a page request with them as one page.
enum ChatPageFixture {
    static func page(_ rows: String, hasOlder: Bool = false, olderCursor: String? = nil, sources: String = "[]")
        -> String
    {
        let cursor = olderCursor.map { "\"\($0)\"" } ?? "null"
        return #"{"messages":\#(rows),"sources":\#(sources),"questions":[],"hasOlder":\#(hasOlder),"olderCursor":\#(cursor)}"#
    }

    /// `body` as one page when `path` asks for a page and `body` is a bare array of rows; otherwise as it is.
    static func wrap(_ body: Data, path: String) -> Data {
        guard path.hasSuffix("/page"), body.first(where: { !$0.isWhitespace }) == UInt8(ascii: "[") else { return body }
        return Data(page(String(decoding: body, as: UTF8.self)).utf8)
    }
}

extension UInt8 {
    fileprivate var isWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}
