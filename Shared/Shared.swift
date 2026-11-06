import Foundation

/// Files exchanged between the host app (has the API key, talks to PlugKit) and the Final Cut panel (sandboxed, no network):
/// accounts.json  host -> panel   profiles and connected accounts, cached from the API
/// job.json       panel <-> host  what the next export will do (accounts, caption, date)
/// history.json   host -> panel   result of the last uploads
enum Shared {
    static var dir: URL {
        // The real home, also from inside a sandbox (NSHomeDirectory would return the container).
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let d = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/PlugKit Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        let url = dir.appendingPathComponent(name)
        if (try? Data(contentsOf: url)) != data { try? data.write(to: url, options: .atomic) }
    }
}

struct ProfileInfo: Codable, Identifiable, Hashable { var id: String; var name: String }

struct AccountInfo: Codable, Identifiable, Hashable {
    var id: String
    var profileId: String
    var platform: String
    var username: String
    var label: String { "\(platform.capitalized) · \(username)" }
}

struct Directory: Codable { var profiles: [ProfileInfo]; var accounts: [AccountInfo]; var updatedAt: Date }

enum PublishMode: String, Codable, CaseIterable, Identifiable {
    case schedule, draft, now
    var id: String { rawValue }
    var title: String {
        switch self {
        case .schedule: return "Planifier"
        case .draft: return "Brouillon"
        case .now: return "Publier tout de suite"
        }
    }
}

struct Job: Codable, Equatable {
    var profileId: String?
    var accountIds: [String] = []
    var caption = ""
    var mode = PublishMode.schedule
    var scheduledAt = Job.tomorrowEvening
    var timezone = TimeZone.current.identifier

    static var tomorrowEvening: Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: 1, to: Date())!
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
    }

    /// Why this job cannot be sent yet, nil when it is ready.
    var problem: String? {
        if accountIds.isEmpty || profileId == nil { return "Choisissez au moins un compte." }
        if mode == .schedule && scheduledAt < Date().addingTimeInterval(60) { return "La date de planification est déjà passée." }
        return nil
    }
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var file: String
    var ok: Bool
    var detail: String
    var scheduledAt: Date?
}
