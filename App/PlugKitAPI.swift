import Foundation

struct APIError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Minimal PlugKit REST client (https://docs.plugkit.co). Responses are read loosely: ids may be `id` or `_id`.
struct PlugKitAPI {
    let key: String
    let base = URL(string: ProcessInfo.processInfo.environment["PLUGKIT_BASE"] ?? "https://api.plugkit.co/v1")!

    func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Any {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        guard (200 ..< 300).contains(code) else {
            let m = (json as? [String: Any]).flatMap { $0["message"] ?? $0["error"] }
            let text = m.map { "\($0)" } ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError(message: code == 401 ? "Clé API refusée (401)." : "PlugKit \(code) : \(text.prefix(300))")
        }
        return json ?? [:]
    }

    private func rows(_ json: Any, _ keys: [String]) -> [[String: Any]] {
        if let list = json as? [[String: Any]] { return list }
        guard let dict = json as? [String: Any] else { return [] }
        for k in keys { if let list = dict[k] as? [[String: Any]] { return list } }
        return []
    }

    private func id(_ d: [String: Any]) -> String? { (d["id"] as? String) ?? (d["_id"] as? String) }

    /// Profiles and the connected accounts that can receive a video post.
    func fetchDirectory() async throws -> Directory {
        let profiles = rows(try await call("GET", "/profiles"), ["profiles", "data"]).compactMap { d -> ProfileInfo? in
            guard let id = id(d) else { return nil }
            return ProfileInfo(id: id, name: d["name"] as? String ?? id)
        }
        let postless: Set<String> = ["whatsapp", "meta_ads", "google_ads"]
        let accounts = rows(try await call("GET", "/accounts", query: ["limit": "100"]), ["accounts", "data"]).compactMap { d -> AccountInfo? in
            guard let id = id(d), let profileId = d["profileId"] as? String,
                  let platform = (d["platform"] as? String)?.lowercased(),
                  !postless.contains(platform), (d["isActive"] as? Bool) ?? true else { return nil }
            return AccountInfo(id: id, profileId: profileId, platform: platform,
                               username: (d["username"] as? String) ?? (d["displayName"] as? String) ?? id)
        }
        return Directory(profiles: profiles, accounts: accounts, updatedAt: Date())
    }

    /// Single-use upload ticket, then one PUT of the file straight to storage. Returns the URL PlugKit will serve it from.
    func upload(_ file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard let ticket = try await call("POST", "/media/upload-url", body: ["filename": file.lastPathComponent]) as? [String: Any],
              let uploadURL = (ticket["uploadUrl"] as? String).flatMap(URL.init),
              let mediaURL = (ticket["mediaUrl"] as? String).flatMap(URL.init)
        else { throw APIError(message: "PlugKit n'a pas renvoyé de lien d'envoi.") }
        if let limit = ticket["singlePutMaxBytes"] as? Int, size > limit {
            throw APIError(message: "Fichier trop gros pour un envoi direct (\(size / 1_000_000) Mo, maximum \(limit / 1_000_000) Mo).")
        }

        var put = URLRequest(url: uploadURL)
        put.httpMethod = (ticket["uploadMethod"] as? String) ?? "PUT"
        put.timeoutInterval = 900
        put.setValue(file.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4", forHTTPHeaderField: "Content-Type")
        let delegate = ProgressDelegate(progress)
        let (data, response) = try await URLSession.shared.upload(for: put, fromFile: file, delegate: delegate)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(code) else {
            throw APIError(message: "Envoi du fichier refusé (\(code)) : \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
        }

        // Tells PlugKit the direct upload is over; the docs give no body, and the file may already be registered without it.
        if let page = (ticket["uploadPageUrl"] as? String).flatMap(URL.init) {
            _ = try? await call("POST", "/media/uploads/\(page.lastPathComponent)/complete", body: [:])
        }
        return mediaURL
    }

    /// Creates the post: scheduled, draft or immediate. Returns the post id when the API gives one.
    func createPost(_ job: Job, media: URL, title: String) async throws -> String? {
        guard let profileId = job.profileId else { throw APIError(message: "Aucun profil.") }
        var body: [String: Any] = [
            "profileId": profileId,
            "accountIds": job.accountIds,
            "content": job.caption,
            "title": String(title.prefix(100)),
            "mediaItems": [["type": "video", "url": media.absoluteString]],
        ]
        switch job.mode {
        case .schedule:
            body["scheduledFor"] = ISO8601DateFormatter().string(from: job.scheduledAt) // absolute (Z), so the timezone only labels it
            body["timezone"] = job.timezone
        case .draft: body["asDraft"] = true
        case .now: body["publishNow"] = true
        }
        let json = try await call("POST", "/posts", body: body)
        guard let d = json as? [String: Any] else { return nil }
        return id(d) ?? (d["post"] as? [String: Any]).flatMap(id)
    }
}

final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }
    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData b: Int64, totalBytesSent sent: Int64,
                    totalBytesExpectedToSend total: Int64) {
        onProgress(Double(sent) / Double(max(total, 1)))
    }
}
