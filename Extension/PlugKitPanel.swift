import Cocoa
import SwiftUI
import ProExtensionHost

struct PanelView: View {
    @StateObject private var model = JobModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("PlugKit Export").font(.headline)
                Text("Réglez ci-dessous, puis Fichier > Partager > PlugKit. La vidéo est exportée, envoyée sur PlugKit et planifiée.")
                    .font(.caption).foregroundStyle(.secondary)
                JobEditor(model: model)
                if !model.history.isEmpty {
                    Divider()
                    Text("Derniers envois").font(.caption).foregroundStyle(.secondary)
                    HistoryList(entries: model.history)
                }
            }
            .padding(14)
        }
    }
}

@objc(PlugKitPanelViewController)
final class PlugKitPanelViewController: NSViewController {
    override func loadView() { view = NSHostingView(rootView: PanelView()) }
}
