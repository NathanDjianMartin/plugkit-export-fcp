import SwiftUI

@MainActor
final class JobModel: ObservableObject {
    @Published var directory: Directory?
    @Published var history: [HistoryEntry] = []
    @Published var job = Shared.read(Job.self, "job.json") ?? Job() {
        didSet { if !reloading { Shared.write(job, "job.json") } }
    }
    private var reloading = false
    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Both sides write these files; pick up the other side's changes.
    func reload() {
        directory = Shared.read(Directory.self, "accounts.json")
        history = Shared.read([HistoryEntry].self, "history.json") ?? []
        if let stored = Shared.read(Job.self, "job.json"), stored != job {
            reloading = true; job = stored; reloading = false
        }
    }

    func toggle(_ account: AccountInfo) {
        if job.accountIds.contains(account.id) {
            job.accountIds.removeAll { $0 == account.id }
        } else {
            // One post targets one profile: picking an account of another profile replaces the selection.
            if job.profileId != account.profileId { job.accountIds = [] }
            job.profileId = account.profileId
            job.accountIds.append(account.id)
        }
        if job.accountIds.isEmpty { job.profileId = nil }
    }

    func appendHistory(_ entry: HistoryEntry) {
        history = Array(([entry] + (Shared.read([HistoryEntry].self, "history.json") ?? [])).prefix(30))
        Shared.write(history, "history.json")
    }
}

/// Destination settings, shown in the Final Cut panel and in the app window.
struct JobEditor: View {
    @ObservedObject var model: JobModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $model.job.mode) {
                ForEach(PublishMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            accounts

            VStack(alignment: .leading, spacing: 4) {
                Text("Légende").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $model.job.caption)
                    .font(.body).frame(minHeight: 70, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }

            if model.job.mode == .schedule {
                DatePicker("Date de publication", selection: $model.job.scheduledAt, in: Date()...)
                Text("Fuseau : \(model.job.timezone)").font(.caption).foregroundStyle(.secondary)
            }

            if let problem = model.job.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var accounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Comptes").font(.caption).foregroundStyle(.secondary)
            if let dir = model.directory, !dir.accounts.isEmpty {
                ForEach(dir.profiles) { profile in
                    let list = dir.accounts.filter { $0.profileId == profile.id }
                    if !list.isEmpty {
                        if dir.profiles.count > 1 { Text(profile.name).font(.caption.bold()) }
                        ForEach(list) { account in
                            Toggle(account.label, isOn: Binding(
                                get: { model.job.accountIds.contains(account.id) },
                                set: { _ in model.toggle(account) }))
                        }
                    }
                }
            } else {
                Text("Aucun compte. Ouvrez l'app PlugKit Export et entrez votre clé API.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HistoryList: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries.prefix(6)) { e in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: e.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(e.ok ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.file).lineLimit(1)
                        Text(e.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
    }
}
