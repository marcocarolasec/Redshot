import SwiftUI

@MainActor
struct HistoryView: View {
    @EnvironmentObject var store: ClipStore
    @FocusState private var searchFocused: Bool
    @AppStorage(Prefs.clipboardPaused) private var paused = false
    @ObservedObject private var l10n = Localizer.shared

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(.regularMaterial)
        .onAppear { store.reload() }
        .task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            searchFocused = true
        }
        .onExitCommand { HistoryPanelController.shared.hide() }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Search text, OCR, app…"), text: $store.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    if let first = store.items.first { select(first) }
                }

            Picker("Type", selection: $store.kindFilter) {
                Text(L("All types")).tag(ClipKind?.none)
                ForEach(ClipKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.symbol).tag(ClipKind?.some(kind))
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("App", selection: $store.appFilter) {
                Text(L("All apps")).tag(String?.none)
                ForEach(store.apps, id: \.bundle) { app in
                    Text(app.name).tag(String?.some(app.bundle))
                }
            }
            .labelsHidden()
            .frame(width: 170)

            Menu {
                Button(L("Area  ⌃⌘S")) { ScreenshotService.shared.capture(.region) }
                Button(L("Window  ⌃⌘W")) { ScreenshotService.shared.capture(.window) }
                Button(L("Full screen  ⌃⌘F")) { ScreenshotService.shared.capture(.screen) }
            } label: {
                Label(L("Capture"), systemImage: "camera.viewfinder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text(store.search.isEmpty ? L("Nothing saved yet") : L("No results"))
                    .foregroundStyle(.secondary)
                Text(L("Copy something or take a screenshot with ⌃⌘S"))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.items) { item in
                        ClipCardView(item: item, onSelect: { select(item) })
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Pie

    private var footer: some View {
        HStack {
            Text(LF("%d items", store.items.count))
                .font(.caption).foregroundStyle(.secondary)
            if let err = store.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            Toggle(L("Pause clipboard"), isOn: $paused)
                .toggleStyle(.switch).controlSize(.mini)
            Button(L("Clear (keeps pinned)")) { store.clearUnpinned() }
                .controlSize(.small)
            Button(L("Settings")) {
                HistoryPanelController.shared.hide()
                SettingsOpener.open()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func select(_ item: ClipItem) {
        HistoryPanelController.shared.hide()
        PasteService.copyAndPaste(item)
    }
}
