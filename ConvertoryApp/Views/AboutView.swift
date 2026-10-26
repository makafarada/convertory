import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Convertory").font(.title2.bold())
                        Text("Scan, combine, edit and read your documents without leaving your iPhone.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Your privacy") {
                    Label("Files are processed on this iPhone only.", systemImage: "iphone")
                    Label("Convertory has no network access of its own: nothing is uploaded.", systemImage: "icloud.slash")
                    Label("No account, no tracking, no ads.", systemImage: "hand.raised")
                    Label("Camera is used only by the document scanner you open.", systemImage: "camera")
                }
                .font(.subheadline)

                Section("Where your files are") {
                    Text("Everything you create is saved in the Files app under On My iPhone › Convertory. Delete it there or from the Library tab.")
                        .font(.subheadline)
                }

                Section {
                    Link(destination: URL(string: "https://convertory.net/privacy.html")!) {
                        Label("Privacy policy", systemImage: "link")
                    }
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
