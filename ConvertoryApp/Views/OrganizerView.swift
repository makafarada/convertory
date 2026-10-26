import SwiftUI

/// Page-by-page editor for the Organize tool: drag to reorder, rotate, or delete pages.
struct OrganizerView: View {
    @ObservedObject var model: ToolModel
    @State private var editMode = EditMode.active

    var body: some View {
        List {
            Section {
                ForEach(model.pageEdits) { edit in
                    PageRow(model: model, edit: edit)
                }
                .onMove { model.pageEdits.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { model.pageEdits.remove(atOffsets: $0) }
                .listRowBackground(Theme.card)
            } header: {
                Text("\(model.pageEdits.count) page\(model.pageEdits.count == 1 ? "" : "s")")
            } footer: {
                Text("Drag the handle to reorder, tap the rotate button to turn a page, swipe or use the red button to remove it.")
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
    }
}

private struct PageRow: View {
    @ObservedObject var model: ToolModel
    let edit: Engine.PageEdit
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(Double(edit.rotation)))
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: 64, height: 84)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(.snappy, value: edit.rotation)

            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(edit.sourceIndex + 1)").font(.body.weight(.medium))
                if edit.rotation != 0 {
                    Text("Rotated \(edit.rotation)°").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { model.rotate(edit) } label: {
                Image(systemName: "rotate.right").font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rotate page \(edit.sourceIndex + 1)")
        }
        .task(id: edit.sourceIndex) {
            image = model.thumbnail(for: edit)
        }
    }
}
