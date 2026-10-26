import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationStack {
            Group {
                if library.files.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "tray",
                        description: Text("Files you make with Convertory are kept here and in the Files app under “On My \(UIDevice.current.model) › Convertory”.")
                    )
                } else {
                    List {
                        ForEach(library.files) { file in
                            NavigationLink(value: file) { Row(file: file) }
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { library.files[$0] }
                            doomed.forEach(library.delete)
                        }
                        .listRowBackground(Theme.card)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ScreenBackground())
            .navigationTitle("Library")
            .navigationDestination(for: LibraryFile.self) { ResultView(file: $0) }
            .toolbar { if !library.files.isEmpty { ToolbarItem(placement: .topBarTrailing) { EditButton() } } }
            .onAppear { library.reload() }
        }
    }
}

private struct Row: View {
    let file: LibraryFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.kind.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title).lineLimit(1).truncationMode(.middle)
                Text("\(file.kind.label) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) · \(file.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
