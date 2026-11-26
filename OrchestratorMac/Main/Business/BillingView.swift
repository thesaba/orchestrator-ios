import Charts
import OrchestratorKit
import SwiftUI

/// Recurring revenue, what is owed and how old it is, the last 12 months, and the invoices
/// with Record Payment and Void.
struct BillingView: View {
    let environment: AppEnvironment

    enum Filter: String, CaseIterable, Identifiable {
        case open = "Unpaid", overdue = "Overdue", paid = "Paid", all = "All"
        var id: String { rawValue }
    }

    @State private var overview: BillingOverview?
    @State private var invoices: [Invoice] = []
    @State private var filter: Filter = .open
    @State private var error: String?
    @State private var loaded = false
    @State private var paying: Invoice?
    @State private var chartExpanded = false

    private var executor: CommandExecutor { environment.executor }
    private var currency: String { overview?.currencyCode ?? "GEL" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusDangerText)
                }
                if !loaded {
                    SkeletonTiles()
                    HStack(alignment: .top, spacing: 16) { SkeletonChart(height: 220); SkeletonRows(count: 4).frame(width: 340) }
                    SkeletonRows(count: 6)
                } else {
                    tiles
                    HStack(alignment: .top, spacing: 16) {
                        chartCard.frame(maxWidth: .infinity, alignment: .topLeading)
                        agingCard.frame(width: 340, alignment: .topLeading)
                    }
                    .appearIn(delay: 0.08)
                    invoicesCard.appearIn(delay: 0.16)
                }
            }
            .padding(24)
        }
        .task { await load() }
        .sheet(isPresented: $chartExpanded) { BillingChartSheet(invoices: invoices, currency: currency) }
        .sheet(item: $paying) { invoice in
            PaymentSheet(invoice: invoice) { amount, method, reference in
                Task {
                    if await executor.recordPayment(invoice: invoice, amountMinorUnits: amount, method: method, reference: reference) {
                        paying = nil
                        await load()
                    }
                }
            }
        }
    }

    private func load() async {
        let api = environment.api
        async let summary = try? api.billingOverview()
        do {
            invoices = try await api.invoices()
            error = nil
        } catch {
            self.error = APIError.wrap(error).errorDescription
        }
        overview = await summary
        loaded = true
    }

    // MARK: - Tiles

    private var tiles: some View {
        let overdue = invoices.filter(\.isOverdue)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            tile("MRR", Money.string(overview?.mrr, currency: currency), "\(overview?.subscriptions ?? 0) subscriptions")
            tile("Outstanding", Money.string(overview?.outstanding, currency: currency),
                 "\(invoices.filter(\.isOpen).count) unpaid invoices")
            tile("Overdue", Money.string(overdue.reduce(0) { $0 + $1.outstanding }, currency: currency),
                 overdue.isEmpty ? "none" : "\(overdue.count) invoices", tint: overdue.isEmpty ? nil : .statusDangerText)
            tile("Clients", overview?.clients.map(String.init) ?? "—",
                 [overview?.suspended.map { "\($0) suspended" }, overview?.pastDue.map { "\($0) past due" }]
                    .compactMap { $0 }.joined(separator: " · ").ifEmpty("all in good standing"),
                 tint: (overview?.suspended ?? 0) > 0 ? .statusWarningText : nil)
        }
    }

    private func tile(_ caption: String, _ value: String, _ detail: String, tint: Color? = nil) -> some View {
        let icons: [String: (String, Color)] = [
            "MRR": ("arrow.triangle.2.circlepath", Vivid.green), "Outstanding": ("tray.full.fill", Vivid.blue),
            "Overdue": ("exclamationmark.circle.fill", Vivid.pink), "Clients": ("person.2.fill", Vivid.purple)
        ]
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let icon = icons[caption] { IconBadge(symbol: icon.0, tint: icon.1) }
            }
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(tint ?? .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    private var chartCard: some View {
        let months = BillingMonth.last(12, of: invoices, currency: currency)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Last 12 months · \(currency)", symbol: "chart.bar.fill", tint: Vivid.green)
                ExpandChartButton { chartExpanded = true }
            }
            VStack(alignment: .leading, spacing: 8) {
                MonthBarsChart(months: months, currency: currency)
                    .frame(height: 180)
                .accessibilityLabel("Invoiced and collected per month for the last 12 months")
            }
            .padding(12)
            .card()
        }
    }

    private var agingCard: some View {
        let aging = overview?.aging
        let buckets: [(String, Int, Color)] = [
            ("Not yet due", aging?.current ?? 0, .chartCPU),
            ("1–30 days", aging?.d1_30 ?? 0, .brandTeal),
            ("31–60 days", aging?.d31_60 ?? 0, .statusWarning),
            ("Over 60 days", aging?.d61_plus ?? 0, .statusDanger)
        ]
        let total = max(1, buckets.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Unpaid by age", symbol: "hourglass", tint: Vivid.orange)
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(buckets, id: \.0) { bucket in
                            if bucket.1 > 0 {
                                Rectangle().fill(bucket.2).frame(width: max(2, proxy.size.width * CGFloat(bucket.1) / CGFloat(total)))
                            }
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                ForEach(buckets, id: \.0) { bucket in
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(bucket.2).frame(width: 10, height: 10).accessibilityHidden(true)
                        Text(bucket.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.string(bucket.1, currency: currency)).monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .card()
        }
    }

    // MARK: - Invoices

    private var shown: [Invoice] {
        invoices.filter { invoice in
            switch filter {
            case .open:    return invoice.isOpen
            case .overdue: return invoice.isOverdue
            case .paid:    return invoice.status.lowercased() == "paid"
            case .all:     return true
            }
        }
        .sorted { ($0.dueDate ?? $0.issuedAt ?? .distantPast) > ($1.dueDate ?? $1.issuedAt ?? .distantPast) }
    }

    private var invoicesCard: some View {
        let shown = self.shown
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Invoices", symbol: "doc.text.fill", tint: Vivid.green)
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                Spacer()
                Button("New Invoice in Web Panel") { WebPanel.open(.home) }.controlSize(.small)
            }
            if shown.isEmpty {
                LoadingOrEmptyRow(isLoading: !loaded, text: "No invoices here", symbol: "doc.text")
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Number").frame(width: 100, alignment: .leading)
                        Text("Client").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Due").frame(width: 100, alignment: .leading)
                        Text("Amount").frame(width: 100, alignment: .trailing)
                        Text("Owed").frame(width: 100, alignment: .trailing)
                        Text("Status").frame(width: 80, alignment: .trailing)
                        Spacer().frame(width: 150)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    ForEach(shown.prefix(200)) { invoice in
                        Divider()
                        InvoiceRow(invoice: invoice,
                                   pay: { paying = invoice },
                                   void: { Task { if await executor.voidInvoice(invoice) { await load() } } })
                    }
                }
                .card()
            }
        }
    }
}

private struct InvoiceRow: View {
    var invoice: Invoice
    var pay: () -> Void
    var void: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(invoice.number ?? "#\(invoice.id)")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(invoice.client?.name ?? "—").lineLimit(1)
                if let domain = invoice.site?.domain {
                    Text(domain).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(invoice.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                .foregroundStyle(invoice.isOverdue ? Color.statusDangerText : .secondary)
                .frame(width: 100, alignment: .leading)
            Text(Money.string(invoice.amount, currency: invoice.currencyCode)).monospacedDigit()
                .frame(width: 100, alignment: .trailing)
            Text(invoice.isOpen ? Money.string(invoice.outstanding, currency: invoice.currencyCode) : "—").monospacedDigit()
                .foregroundStyle(invoice.isOpen ? .primary : .secondary)
                .frame(width: 100, alignment: .trailing)
            Text(invoice.isOverdue ? "Overdue" : invoice.status.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(invoice.isOverdue ? Color.statusDangerText : invoice.tone.color)
                .frame(width: 80, alignment: .trailing)
            HStack(spacing: 6) {
                if invoice.isOpen {
                    Button("Record Payment…", action: pay).buttonStyle(RowButtonStyle())
                    Button(action: void) { Image(systemName: "xmark.circle") }
                        .buttonStyle(RowButtonStyle())
                        .help("Void this invoice (Touch ID)")
                        .accessibilityLabel("Void \(invoice.number ?? "invoice")")
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}

/// Amount (defaults to what is owed), method and an optional reference.
private struct PaymentSheet: View {
    let invoice: Invoice
    var record: (Int, OrchestratorAPI.PaymentMethod, String?) -> Void

    @State private var amountText = ""
    @State private var method: OrchestratorAPI.PaymentMethod = .bank
    @State private var reference = ""
    @Environment(\.dismiss) private var dismiss

    private var amountMinor: Int? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        var minor = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &minor, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record a payment on \(invoice.number ?? "#\(invoice.id)")").font(.headline)
            Text("\(invoice.client?.name ?? "Client") owes \(Money.string(invoice.outstanding, currency: invoice.currencyCode)). Recording a payment changes the books only; no money moves.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Amount (\(invoice.currencyCode))", text: $amountText)
                Picker("Method", selection: $method) {
                    ForEach(OrchestratorAPI.PaymentMethod.allCases) { Text($0.title).tag($0) }
                }
                TextField("Reference (optional)", text: $reference)
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Record…") {
                    if let amountMinor { record(amountMinor, method, reference.isEmpty ? nil : reference) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(amountMinor == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            amountText = NSDecimalNumber(decimal: Money.decimal(invoice.outstanding)).stringValue
        }
    }
}
