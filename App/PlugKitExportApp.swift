import SwiftUI
import UserNotifications

@main
struct PlugKitExportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("PlugKit Export", id: "main") {
            HostView(host: HostModel.shared).frame(width: 460)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        Task { @MainActor in HostModel.shared.start() }
    }

    /// Final Cut hands the exported movie over here ("Open with Application" job action of the share destination).
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in HostModel.shared.receive(urls) }
    }
}

struct UploadItem: Identifiable {
    let id = UUID()
    var name: String
    var stage = "Préparation…"
    var progress = 0.0
}

@MainActor
final class HostModel: ObservableObject {
    static let shared = HostModel()

    let jobs = JobModel()
    @Published var apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }
    @Published var status = ""
    @Published var busy = false
    @Published var uploads: [UploadItem] = []
    @Published var pending: URL?          // exported movie waiting for a valid job
    @Published var destinationInstalled = UserDefaults.standard.bool(forKey: "destinationInstalled")

    private static let extensionID = "com.nathan.plugkitexport.extension"

    func start() {
        registerExtension()
        if !destinationInstalled { installDestination() }
        if !apiKey.isEmpty && jobs.directory == nil { Task { await connect() } }
    }

    // MARK: Account

    func connect() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        busy = true; status = "Connexion à PlugKit…"
        do {
            let dir = try await PlugKitAPI(key: key).fetchDirectory()
            Shared.write(dir, "accounts.json")
            jobs.reload()
            status = "Connecté : \(dir.accounts.count) compte(s)."
        } catch {
            status = "Erreur : \(error.localizedDescription)"
        }
        busy = false
    }

    // MARK: Final Cut integration

    /// Makes the panel appear in Window > Extensions (the appex sits inside this app; macOS only needs to be told).
    func registerExtension() {
        guard let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("PlugKitExportExt.appex") else { return }
        let ls = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for (tool, args) in [(ls, ["-f", "-R", "-trusted", Bundle.main.bundlePath]),
                             ("/usr/bin/pluginkit", ["-a", appex.path]),
                             ("/usr/bin/pluginkit", ["-e", "use", "-i", Self.extensionID])] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
            try? p.run()
            p.waitUntilExit()
        }
    }

    /// Final Cut installs a share destination when it is asked to open its .fcpxdest file.
    func installDestination() {
        guard let dest = Bundle.main.url(forResource: "PlugKit", withExtension: "fcpxdest"),
              let fcp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FinalCut") else {
            status = "Final Cut Pro est introuvable."
            return
        }
        NSWorkspace.shared.open([dest], withApplicationAt: fcp, configuration: NSWorkspace.OpenConfiguration())
        UserDefaults.standard.set(true, forKey: "destinationInstalled")
        destinationInstalled = true
        status = "Destination « PlugKit » envoyée à Final Cut Pro (Fichier > Partager)."
    }

    // MARK: Uploads

    func receive(_ urls: [URL]) {
        let movies = urls.filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
        NSApp.activate(ignoringOtherApps: true)
        for url in movies { Task { await send(url) } }
    }

    func retryPending() {
        guard let url = pending else { return }
        pending = nil
        Task { await send(url) }
    }

    private func send(_ file: URL) async {
        jobs.reload()
        let job = jobs.job
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { pending = file; status = "Entrez d'abord votre clé API PlugKit."; return }
        if let problem = job.problem { pending = file; status = "\(problem) Puis « Envoyer »."; return }

        let item = UploadItem(name: file.deletingPathExtension().lastPathComponent)
        uploads.insert(item, at: 0)
        func update(_ change: (inout UploadItem) -> Void) {
            if let i = uploads.firstIndex(where: { $0.id == item.id }) { change(&uploads[i]) }
        }
        do {
            let api = PlugKitAPI(key: key)
            update { $0.stage = "Envoi vers PlugKit…" }
            let media = try await api.upload(file) { p in Task { @MainActor in update { $0.progress = p } } }
            update { $0.stage = job.mode == .schedule ? "Planification…" : "Création du post…"; $0.progress = 1 }
            _ = try await api.createPost(job, media: media, title: item.name)

            let when = job.scheduledAt.formatted(date: .abbreviated, time: .shortened)
            let detail = switch job.mode {
            case .schedule: "Planifié le \(when) sur \(job.accountIds.count) compte(s)."
            case .draft: "Brouillon créé sur PlugKit."
            case .now: "Publication lancée."
            }
            jobs.appendHistory(HistoryEntry(file: item.name, ok: true, detail: detail,
                                            scheduledAt: job.mode == .schedule ? job.scheduledAt : nil))
            if job.mode == .schedule { jobs.job.scheduledAt = job.scheduledAt.addingTimeInterval(86400) } // next video, next day
            notify("PlugKit : \(item.name)", detail)
            status = detail
        } catch {
            jobs.appendHistory(HistoryEntry(file: item.name, ok: false, detail: error.localizedDescription))
            notify("PlugKit : échec", error.localizedDescription)
            status = "Erreur : \(error.localizedDescription)"
        }
        uploads.removeAll { $0.id == item.id }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

struct HostView: View {
    @ObservedObject var host: HostModel
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Compte PlugKit") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Clé API (sk_…)", text: $host.apiKey).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Se connecter") { Task { await host.connect() } }.disabled(host.busy || host.apiKey.isEmpty)
                            if let dir = host.jobs.directory {
                                Text("\(dir.accounts.count) compte(s) · \(dir.profiles.count) profil(s)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(6)
                }

                GroupBox("Final Cut Pro") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fichier > Partager > PlugKit exporte le projet et l'envoie ici ; il part ensuite sur PlugKit avec les réglages ci-dessous (ou ceux du panneau Fenêtre > Extensions > PlugKit Export).")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(host.destinationInstalled ? "Réinstaller la destination" : "Installer la destination") {
                                host.installDestination()
                            }
                            Button("Réenregistrer l'extension") { host.registerExtension() }
                        }
                    }.padding(6)
                }

                GroupBox("Prochain envoi") { JobEditor(model: host.jobs).padding(6) }

                if let pending = host.pending {
                    GroupBox {
                        HStack {
                            Text("« \(pending.deletingPathExtension().lastPathComponent) » attend ses réglages.")
                            Spacer()
                            Button("Envoyer") { host.retryPending() }.keyboardShortcut(.defaultAction)
                        }.padding(6)
                    }
                }

                ForEach(host.uploads) { u in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(u.name) — \(u.stage)")
                        ProgressView(value: u.progress)
                    }
                }

                if !host.status.isEmpty { Text(host.status).font(.callout) }
                if !host.jobs.history.isEmpty { GroupBox("Historique") { HistoryList(entries: host.jobs.history).padding(6) } }

                Text("Vous pouvez aussi glisser une vidéo ici pour l'envoyer.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(minHeight: 560)
        .overlay { if targeted { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(4) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in host.receive([url]) } }
                }
            }
            return true
        }
    }
}
