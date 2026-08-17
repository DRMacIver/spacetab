import AppKit
import SwiftUI
import SpaceTabCore

final class SwitcherState: ObservableObject {
    @Published var model: SwitcherModel?
    @Published var maxColumnHeight: CGFloat = 600
}

struct SwitcherView: View {
    @ObservedObject var state: SwitcherState

    var body: some View {
        if let model = state.model {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(model.columns.enumerated()), id: \.element.id) { colIndex, column in
                    columnView(column,
                               index: colIndex,
                               isSelectedColumn: colIndex == model.selectedColumn,
                               selectedRow: model.selectedRow)
                }
            }
            .padding(16)
        }
    }

    private func columnView(_ column: SpaceColumn, index: Int,
                            isSelectedColumn: Bool, selectedRow: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Space \(index + 1)\(column.isCurrent ? " ●" : "")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelectedColumn ? .primary : .secondary)
                .padding(.bottom, 2)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(column.windows.enumerated()), id: \.element.id) { rowIndex, window in
                            row(window, selected: isSelectedColumn && rowIndex == selectedRow)
                                .id(window.id)
                        }
                        if column.windows.isEmpty {
                            Text("—").foregroundStyle(.tertiary).font(.system(size: 12))
                        }
                    }
                }
                .frame(maxHeight: state.maxColumnHeight)
                .onAppear { scrollToSelection(proxy, column, isSelectedColumn, selectedRow) }
                .onChange(of: selectedRow) { _ in
                    scrollToSelection(proxy, column, isSelectedColumn, selectedRow)
                }
                .onChange(of: isSelectedColumn) { _ in
                    scrollToSelection(proxy, column, isSelectedColumn, selectedRow)
                }
            }
        }
        .frame(width: 230, alignment: .leading)
        .padding(6)
        .background(isSelectedColumn ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy, _ column: SpaceColumn,
                                   _ isSelectedColumn: Bool, _ selectedRow: Int) {
        guard isSelectedColumn, column.windows.indices.contains(selectedRow) else { return }
        proxy.scrollTo(column.windows[selectedRow].id)
    }

    private func row(_ window: WindowEntry, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(window.appName).font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !window.title.isEmpty && window.title != window.appName {
                    Text(window.title).font(.system(size: 10))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if window.hasModal {
                Spacer(minLength: 4)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help("A dialog is blocking this window")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.4) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}

final class SwitcherPanel {
    let state = SwitcherState()
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
            SwitcherView(state: state)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))))
        panel.contentView = hosting
    }

    func show(model: SwitcherModel) {
        update(model: model)
        panel.orderFrontRegardless()
    }

    func update(model: SwitcherModel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        state.maxColumnHeight = visible.height * 0.7
        state.model = model
        // Let SwiftUI lay out the new content before asking for its size.
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width = min(size.width, visible.width - 40)
        size.height = min(size.height, visible.height - 40)
        panel.setFrame(
            NSRect(x: visible.midX - size.width / 2,
                   y: visible.midY - size.height / 2,
                   width: size.width, height: size.height),
            display: true)
    }

    func hide() {
        panel.orderOut(nil)
        state.model = nil
    }
}
