import Models

/// A group's saved rows, grown by the re-read after a `message_end` (`?after=`).
public enum GroupHistory {
    /// `rows` after `held`, one row per id (an id already held keeps its place and takes the newer copy).
    public static func append(_ held: [GroupMessage], _ rows: [GroupMessage]) -> [GroupMessage] {
        var result: [GroupMessage] = []
        var index: [String: Int] = [:]
        for row in held + rows {
            if let i = index[row.id] {
                result[i] = row
            } else {
                index[row.id] = result.count
                result.append(row)
            }
        }
        return result
    }
}
