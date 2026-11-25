import AppKit
import OrchestratorKit
import SwiftUI

/// The full deploy log window, about 1120 × 648, resizable.
@MainActor
final class DeployLogWindowController: NSObject, NSWindowDelegate {
    let model: DeployLogWindowModel
    private unowned let coordinator: LogCoordinator
    private let window: NSWindow

    init(model: DeployLogWindowModel, coordinator: LogCoordinator) {
        self.model = model
        self.coordinator = coordinator
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 648),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "\(model.domain) — Deploy log"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 820, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("DeployLogWindow")

        let siteID = model.siteID
        let view = DeployLogWindowView(model: model) { [weak coordinator] in
            coordinator?.shrink(siteID: siteID)
        }
        let controller = NSHostingController(rootView: view)
        // The window sizes the view, never the other way round (avoids constraint-pass loops).
        controller.sizingOptions = [.minSize]
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1120, height: 648))
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await model.load() }
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        coordinator.windowDidClose(siteID: model.siteID)
    }
}

struct DeployLogWindowView: View {
    @Bindable var model: DeployLogWindowModel
    var onShrink: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                DeployLogSidebar(model: model)
                    .frame(width: 280)
                Divider()
                VStack(spacing: 0) {
                    infoStrip
                    Divider()
                    LogLinesView(lines: model.visibleLines, fontSize: 12,
                                 follow: model.isShowingLive && model.search.isEmpty && !model.errorsOnly,
                                 scrollTarget: model.scrollTarget)
                    if model.status == "failed" {
                        FailureBanner(model: model)
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 420)
        .sheet(isPresented: $model.isShowingExplanation) {
            ExplanationSheet(model: model)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.domain)
                    .font(.system(size: 13, weight: .semibold))
                Text(outcomeText)
                    .font(.system(size: 11))
                    .foregroundStyle(outcomeColor)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            TextField("Search log", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Toggle("Errors only", isOn: $model.errorsOnly)
                .toggleStyle(.button)
            Button("Copy log") { model.copyLog() }
            Button(action: onShrink) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(!model.isShowingLive)
            .help("Shrink to the compact panel")
            .accessibilityLabel("Shrink to compact panel")
        }
        .controlSize(.regular)
        .padding(.leading, 86) // clear the traffic lights
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    private var outcomeText: String {
        let time = model.startedAt?.formatted(date: .omitted, time: .shortened) ?? ""
        let kind = model.isRollback ? "Rollback" : "Deploy"
        switch model.status {
        case "running": return "\(kind) running · started \(time)"
        case "success": return "\(kind) succeeded · \(time)"
        case "failed":  return "\(kind) failed · \(time)"
        default:        return model.deployments.isEmpty && model.isLoadingHistory ? "Loading…" : "No deploys yet"
        }
    }

    private var outcomeColor: Color {
        switch model.status {
        case "success": return .statusSuccessText
        case "failed":  return .statusDangerText
        case "running": return .accentText
        default:        return .secondary
        }
    }

    // MARK: - Info strip

    private var infoStrip: some View {
        HStack {
            Text([model.branch, model.shortCommit, model.summary.commitMessage].compactMap { $0 }.joined(separator: " · "))
                .lineLimit(1)
            Spacer()
            if let started = model.startedAt {
                Text("Started \(started.formatted(date: .omitted, time: .standard)) · ran \(Durations.elapsed(model.durationSeconds))")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
    }
}

// MARK: - Sidebar

private struct DeployLogSidebar: View {
    @Bindable var model: DeployLogWindowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                header("Steps")
                let steps = model.summary.steps
                if steps.isEmpty {
                    Text(model.isRollback ? "A rollback has no steps." : "No steps yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                ForEach(steps) { step in
                    stepRow(step)
                }

                header("Previous deploys").padding(.top, 14)
                if model.live != nil {
                    liveRow
                }
                if let error = model.historyError {
                    Text(error).font(.system(size: 12)).foregroundStyle(Color.statusDangerText).padding(.horizontal, 8)
                }
                ForEach(model.deployments) { deployment in
                    deploymentRow(deployment)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func stepRow(_ step: DeployStep) -> some View {
        Button {
            model.scrollTarget = model.lineID(for: step)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(step.state))
                    .foregroundStyle(color(step.state))
                    .frame(width: 16)
                Text(step.title)
                    .font(.system(size: 13, weight: step.state == .failed ? .semibold : .regular))
                    .foregroundStyle(step.state == .skipped ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(stepDuration(step))
                    .font(.system(size: 11, weight: step.state == .failed ? .semibold : .regular,
                                  design: step.state == .failed ? .default : .monospaced))
                    .foregroundStyle(step.state == .failed ? Color.statusDangerText : .secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(step.state == .failed ? Color.tintDanger : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step.title), \(stateWord(step.state))")
        .accessibilityHint("Scrolls the log to this step")
    }

    private var liveRow: some View {
        Button { model.selectLive() } label: {
            HStack(spacing: 10) {
                StatusMarkView(mark: .deploying, size: 14)
                Text("Live").font(.system(size: 13, weight: model.isShowingLive ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(selectionBackground(model.isShowingLive))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deploymentRow(_ deployment: DeploymentRecord) -> some View {
        let selected = model.selectedDeploymentID == deployment.id
        return Button { model.select(deployment) } label: {
            HStack(spacing: 10) {
                Image(systemName: deployment.status == "success" ? "checkmark" : deployment.status == "running" ? "arrow.up" : "xmark")
                    .foregroundStyle(deployment.status == "success" ? Color.statusSuccess : deployment.status == "running" ? Color.accentText : Color.statusDanger)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(deployment.createdAt?.formatted(.dateTime.day().month(.abbreviated).hour().minute()) ?? "—")
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Text([deployment.branch, deployment.shortCommit].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Durations.elapsed(model.summary(for: deployment).durationSeconds))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectionBackground(selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deployment.status == "success" ? "Succeeded" : deployment.status == "running" ? "Running" : "Failed"), \(deployment.createdAt?.formatted() ?? "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func selectionBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(Color.clear))
    }

    private func stepDuration(_ step: DeployStep) -> String {
        switch step.state {
        case .skipped: return "Skipped"
        case .failed:  return "Failed · \(Durations.elapsed(step.durationSeconds))"
        case .running: return "…"
        case .done:    return Durations.elapsed(step.durationSeconds)
        }
    }

    private func symbol(_ state: DeployStep.State) -> String {
        switch state {
        case .done:    return "checkmark"
        case .failed:  return "xmark"
        case .skipped: return "minus"
        case .running: return "arrow.up"
        }
    }

    private func color(_ state: DeployStep.State) -> Color {
        switch state {
        case .done:    return .statusSuccess
        case .failed:  return .statusDanger
        case .skipped: return .secondary
        case .running: return .accentText
        }
    }

    private func stateWord(_ state: DeployStep.State) -> String {
        switch state {
        case .done:    return "done"
        case .failed:  return "failed"
        case .skipped: return "skipped"
        case .running: return "running"
        }
    }
}

// MARK: - Failure banner

private struct FailureBanner: View {
    let model: DeployLogWindowModel

    var body: some View {
        let summary = model.summary
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color.statusDanger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.failedStep.map { "\(model.isRollback ? "Rollback" : "Deploy") failed at \($0.title)" }
                     ?? "\(model.isRollback ? "Rollback" : "Deploy") failed")
                    .font(.system(size: 13, weight: .semibold))
                Text(siteState(summary))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Copy error") { model.copyError() }
            if !model.isRollback {
                Button("Retry deploy") { model.retry() }
                    .help("Deploys the same branch again, after a confirmation")
            }
            Button("Explain error") { model.explain() }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.tintDanger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(12)
    }

    private func siteState(_ summary: DeployLogSummary) -> String {
        if model.isRollback { return "The release that was live before the rollback is still live." }
        if summary.rolledBack { return "The health check failed and the previous release was restored." }
        if summary.reachedActivation { return "The new release went live before the failure. Check the site." }
        return "The previous release is still live."
    }
}

// MARK: - Explanation

private struct ExplanationSheet: View {
    @Bindable var model: DeployLogWindowModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Explain error", systemImage: "sparkles")
                .font(.headline)
            Group {
                switch model.explanation {
                case .idle, .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Asking the panel's AI about this deploy…").foregroundStyle(.secondary)
                    }
                case .loaded(let text):
                    ScrollView {
                        Text(LocalizedStringKey(text))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.statusDangerText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 420, alignment: .topLeading)

            HStack {
                if case .loaded = model.explanation {
                    Button("Ask again") { model.explain(force: true) }
                        .help("Asks the AI for a fresh explanation")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
