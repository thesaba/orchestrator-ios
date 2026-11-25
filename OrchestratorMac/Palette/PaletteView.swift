import OrchestratorKit
import SwiftUI

/// 640 pt wide, radius 16: a 56 pt search field, grouped results with 44 pt rows, key hints.
struct PaletteView: View {
    @Bindable var model: PaletteModel
    var onHeightChange: (CGFloat) -> Void
    @FocusState private var fieldFocused: Bool
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 8 * 46 + 60

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            results
            Divider()
            footer
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .onAppear { fieldFocused = true }
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: 12) {
            if model.stage != .commands {
                Button {
                    _ = model.back()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to commands")
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            TextField(model.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($fieldFocused)
                .accessibilityLabel("Command")
            KeyCap(text: "esc")
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        let sections = model.sections
        if sections.isEmpty || sections.allSatisfy({ $0.rows.isEmpty }) {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            Text(section.title.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.44)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.rows) { row in
                                PaletteRowView(row: row, isSelected: row.id == model.effectiveSelectedID)
                                    .id(row.id)
                                    .onTapGesture { model.select(row.id); model.activate(.run) }
                                    .onHover { if $0 { model.select(row.id) } }
                            }
                        }
                        if let error = model.stageError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                    }
                    .padding(8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(listHeight, 1), Self.maxListHeight))
                .onChange(of: model.effectiveSelectedID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: nil) }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            if model.isLoadingSites || model.isLoadingStage {
                ProgressView().controlSize(.small)
                Text(model.isLoadingStage ? "Loading…" : "Loading sites…")
            } else if let error = model.stageError {
                Image(systemName: "info.circle")
                Text(error)
            } else {
                Image(systemName: "magnifyingglass")
                Text(model.query.isEmpty ? "Type to search commands" : "No results for “\(model.query)”")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↵", "Run")
            hint("⌘ ↵", "Run and show log")
            if case .command(let command)? = model.selectedRow?.payload, command.kind.acceptsRef {
                hint("⌥ ↵", "Choose branch")
            }
            Spacer()
            let count = model.rows.count
            Text(count == 1 ? "1 result" : "\(count) results")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            KeyCap(text: keys)
            Text(label).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(keys.replacingOccurrences(of: "⌘", with: "Command ").replacingOccurrences(of: "⌥", with: "Option ").replacingOccurrences(of: "↵", with: "Return"))")
    }
}

/// One 44 pt result row: icon tile, title, detail, trailing badges.
private struct PaletteRowView: View {
    var row: PaletteModel.Row
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Color.white.opacity(0.18)) : AnyShapeStyle(.fill.secondary))
                }
            Text(row.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .layoutPriority(1)
            Text(row.detail)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.needsAuthentication {
                KeyCap(text: "Touch ID", onAccent: isSelected)
            }
            if isSelected {
                KeyCap(text: "↵", onAccent: true)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.detail)
        .accessibilityHint(row.needsAuthentication ? "Requires Touch ID or your password" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
