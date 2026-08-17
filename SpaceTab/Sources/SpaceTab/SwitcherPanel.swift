import AppKit
import SwiftUI
import SpaceTabCore

final class SwitcherState: ObservableObject {
    @Published var model: SwitcherModel?
}

struct SwitcherView: View {
    @ObservedObject var state: SwitcherState

    var body: some View {
        if let model = state.model {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(model.columns.enumerated()), id: \.element.id) { colIndex, column in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(column.isCurrent ? "● Space" : "Space")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                        ForEach(Array(column.windows.enumerated()), id: \.element.id) { rowIndex, window in
                            row(window,
                                selected: colIndex == model.selectedColumn
                                    && rowIndex == model.selectedRow)
                        }
                        if column.windows.isEmpty {
                            Text("—").foregroundStyle(.tertiary).font(.system(size: 12))
                        }
                    }
                    .frame(minWidth: 180, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private func row(_ window: WindowEntry, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(window.appName).font(.system(size: 12, weight: .medium))
                if !window.title.isEmpty && window.title != window.appName {
                    Text(window.title).font(.system(size: 10))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.35) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}

final class SwitcherPanel {
    let state = SwitcherState()
    private let panel: NSPanel

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
        let hosting = NSHostingView(rootView:
            SwitcherView(state: state)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)))
        panel.contentView = hosting
    }

    func show(model: SwitcherModel) {
        state.model = model
        panel.setContentSize(panel.contentView!.fittingSize)
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2))
        }
        panel.orderFrontRegardless()
    }

    func update(model: SwitcherModel) {
        state.model = model
        panel.setContentSize(panel.contentView!.fittingSize)
    }

    func hide() {
        panel.orderOut(nil)
        state.model = nil
    }
}
