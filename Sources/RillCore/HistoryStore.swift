import Foundation

/// Minute records on disk, one JSON line each, one file per local day:
/// ~/Library/Application Support/Rill/history/2026-11-04.jsonl.
public final class HistoryStore {
    public let directory: URL
    public let keepDays: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dayFormat: DateFormatter

    public init(directory: URL? = nil, keepDays: Int = 30) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rill/history", isDirectory: true)
        self.keepDays = keepDays
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func file(for date: Date) -> URL {
        directory.appendingPathComponent(dayFormat.string(from: date) + ".jsonl")
    }

    public func append(_ r: MinuteRecord) {
        guard var line = try? encoder.encode(r) else { return }
        line.append(0x0A)
        let url = file(for: r.t)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    /// Records at or after `since`, oldest first. Unreadable lines are skipped.
    public func load(since: Date, now: Date = Date()) -> [MinuteRecord] {
        var out: [MinuteRecord] = []
        let cal = Calendar.current
        var day = cal.startOfDay(for: since)
        while day <= now {
            if let data = try? Data(contentsOf: file(for: day)) {
                for line in data.split(separator: 0x0A) {
                    if let r = try? decoder.decode(MinuteRecord.self, from: line), r.t >= since { out.append(r) }
                }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out.sorted { $0.t < $1.t }
    }

    /// Deletes day files older than `keepDays`.
    public func prune(now: Date = Date()) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Calendar.current.startOfDay(for: now))!
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "jsonl" {
            if let d = dayFormat.date(from: f.deletingPathExtension().lastPathComponent), d < cutoff {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}
