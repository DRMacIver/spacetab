import AppKit
import SwiftUI
import SpaceTabCore

final class LauncherState: ObservableObject {
    @Published var model: LauncherModel?
}

struct LauncherView: View {
    @ObservedObject var state: LauncherState

    var body: some View {
        if let model = state.model {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(model.query.isEmpty ? "Open application or window…" : model.query)
                        .font(.system(size: 20))
                        .foregroundStyle(model.query.isEmpty ? .tertiary : .primary)
                    Rectangle()  // caret
                        .frame(width: 2, height: 22)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 4)
                if !model.results.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.offset) { index, result in
                            row(result, selected: index == model.selected)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 560, alignment: .leading)
        }
    }

    @ViewBuilder
    private func row(_ result: LauncherResult, selected: Bool) -> some View {
        HStack(spacing: 8) {
            switch result {
            case .app(let app):
                icon(pid: app.pid, path: app.path)
                Text(app.name).font(.system(size: 14, weight: .medium))
                if app.pid == nil {
                    Text("Launch").font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("New window").font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            case .window(let w):
                icon(pid: w.window.pid, path: nil)
                Text(w.window.appName).font(.system(size: 14, weight: .medium))
                if !w.window.title.isEmpty {
                    Text(w.window.title).font(.system(size: 12))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "macwindow")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.4) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func icon(pid: pid_t?, path: String?) -> some View {
        if let pid, let image = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: image).resizable().frame(width: 22, height: 22)
        } else if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().frame(width: 22, height: 22)
        } else {
            Image(systemName: "app").frame(width: 22, height: 22)
        }
    }
}

final class LauncherPanel {
    let state = LauncherState()
    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        hosting = NSHostingView(rootView: AnyView(
            LauncherView(state: state)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))))
        panel.contentView = hosting
    }

    func show(model: LauncherModel) {
        update(model: model)
        panel.orderFrontRegardless()
    }

    func update(model: LauncherModel) {
        state.model = model
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        size.width = min(size.width, visible.width - 40)
        size.height = min(size.height, visible.height - 40)
        // Anchor the top edge at 72% of the screen so the panel grows
        // downward as results appear instead of jumping around.
        panel.setFrame(
            NSRect(x: visible.midX - size.width / 2,
                   y: visible.minY + visible.height * 0.72 - size.height,
                   width: size.width, height: size.height),
            display: true)
    }

    func hide() {
        panel.orderOut(nil)
        state.model = nil
    }
}
