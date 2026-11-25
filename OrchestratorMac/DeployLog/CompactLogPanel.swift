import AppKit
import OrchestratorKit
import SwiftUI

/// The small floating log panel, 480 pt wide. Non-activating so it never steals focus.
@MainActor
final class CompactLogPanelController: NSObject, NSWindowDelegate {
    private let session: LogSession
    private unowned let coordinator: LogCoordinator
    private let panel: KeyablePanel
    private let state = CompactPanelState()

    init(session: LogSession, coordinator: LogCoordinator, index: Int) {
        self.session = session
        self.coordinator = coordinator
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
                        backing: .buffered, defer: true)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 480, height: 260)
        panel.delegate = self
        panel.setAccessibilityLabel("Deploy log")

        let siteID = session.siteID
        let view = CompactLogView(
            session: session, state: state,
            onToggleTop: { [weak self] in self?.toggleKeepOnTop() },
            onExpand: { [weak coordinator] in coordinator?.expand(siteID: siteID) },
            onClose: { [weak coordinator] in coordinator?.closeCompact(siteID: siteID) },
            onOpenLastLog: { [weak coordinator] in coordinator?.expandToHistory(siteID: siteID, domain: session.domain) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.minSize]
        panel.contentView = hosting
        place(index: index)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }

    private func toggleKeepOnTop() {
        state.keepOnTop.toggle()
        panel.level = state.keepOnTop ? .floating : .normal
    }

    /// Top right of the screen, cascading for several sites.
    private func place(index: Int) {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let offset = CGFloat(index % 5) * 28
        let origin = NSPoint(x: visible.maxX - 480 - 24 - offset, y: visible.maxY - 380 - 24 - offset)
        panel.setFrameOrigin(origin)
    }
}

@MainActor
@Observable
final class CompactPanelState {
    var keepOnTop = true
    var followOutput = true
}

extension LogCoordinator {
    /// "No deploy running" → the last deploy's log in the full window.
    func expandToHistory(siteID: Int, domain: String) {
        closeCompact(siteID: siteID)
        showWindow(siteID: siteID, domain: domain)
    }
}

struct CompactLogView: View {
    let session: LogSession
    @Bindable var state: CompactPanelState
    var onToggleTop: () -> Void
    var onExpand: () -> Void
    var onClose: () -> Void
    var onOpenLastLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            if session.state == .notRunning {
                notRunning
            } else {
                progress
                LogLinesView(lines: Array(session.lines.suffix(400)), fontSize: 11.5, follow: state.followOutput)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 12)
                footer
            }
        }
        .frame(minWidth: 480, minHeight: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            StatusMarkView(mark: mark, size: 14)
            Text(session.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Text(session.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            panelButton(state.keepOnTop ? "pin.fill" : "pin", active: state.keepOnTop,
                        label: state.keepOnTop ? "Keep on top, on" : "Keep on top, off", action: onToggleTop)
            panelButton("arrow.up.left.and.arrow.down.right", label: "Expand to full window", action: onExpand)
            panelButton("xmark", label: "Close panel", action: onClose)
                .help("Close the panel. The deploy keeps running.")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 42)
        .accessibilityElement(children: .contain)
    }

    private func panelButton(_ symbol: String, active: Bool = false, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary))
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var mark: HealthMark {
        switch session.state {
        case .succeeded:                return .healthy
        case .failed, .cancelled:       return .failure
        case .notRunning:               return .unknown
        case .connecting, .running:     return .deploying
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progress: some View {
        let summary = session.summary
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(stepText(summary))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: session.isFinished ? 86_400 : 1)) { _ in
                    Text(Durations.clock(session.elapsedSeconds))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed \(Durations.elapsed(session.elapsedSeconds))")
                }
            }
            if session.isDeployLike, let total = summary.totalSteps, total > 0 {
                StepSegments(total: total, current: summary.currentStep?.number ?? 0, state: session.state)
            } else if !session.isFinished {
                ProgressView().progressViewStyle(.linear).controlSize(.small)
            }
        }
        .padding(12)
    }

    private func stepText(_ summary: DeployLogSummary) -> String {
        switch session.state {
        case .connecting: return "Connecting…"
        case .succeeded:  return session.isDeployLike ? "Finished" : "Done"
        case .failed:
            if let step = summary.failedStep { return "Failed at step \(step.number) · \(step.title)" }
            return "Failed"
        case .cancelled:  return "Cancelled"
        default:
            if let step = summary.currentStep, let total = summary.totalSteps {
                return "Step \(step.number) of \(total) · \(step.title)"
            }
            return "Running"
        }
    }

    // MARK: - Footer and empty state

    private var footer: some View {
        HStack {
            Toggle("Follow output", isOn: $state.followOutput)
                .toggleStyle(.checkbox)
            Spacer()
            Button("Copy log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.runner.buffer.plainText, forType: .string)
            }
        }
        .font(.system(size: 12))
        .padding(12)
    }

    private var notRunning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing is running on \(session.domain) right now. The deploy may have finished before the log opened.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open the last deploy log", action: onOpenLastLog)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One segment per step: done green, current accent (red when it failed), pending track.
struct StepSegments: View {
    var total: Int
    var current: Int
    var state: LogSession.State

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(total, 1), id: \.self) { step in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: step))
                    .frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(total)")
    }

    private func color(for step: Int) -> Color {
        if state == .succeeded { return .statusSuccess }
        if step < current { return .statusSuccess }
        if step == current {
            return state == .failed || state == .cancelled ? .statusDanger : .accentText
        }
        return .barTrack
    }
}
