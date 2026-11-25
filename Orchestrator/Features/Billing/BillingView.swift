import SwiftUI
import OrchestratorKit

@MainActor
@Observable
final class BillingViewModel {
    private(set) var overview: BillingOverview?
    private(set) var invoices: [Invoice] = []
    private(set) var subscriptions: [Subscription] = []
    private(set) var clients: [BillingClient] = []
    private(set) var profitability: [ProfitabilityRow] = []
    private(set) var enforcement: EnforcementMode?

    private(set) var fatalError: APIError?
    private(set) var degradedSections: [String] = []
    var hasLoadedOnce = false

    let runner = ActionRunner()

    private let api: OrchestratorAPI

    init(api: OrchestratorAPI = .shared) {
        self.api = api
    }

    var currencyCode: String { overview?.currencyCode ?? "GEL" }
    var openInvoices: [Invoice] { invoices.filter(\.isOpen).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) } }
    var overdueInvoices: [Invoice] { invoices.filter(\.isOverdue) }

    func load() async {
        defer { hasLoadedOnce = true }
        fatalError = nil
        var degraded: [String] = []

        async let overviewTask = api.billingOverview()
        async let invoicesTask = api.invoices()
        async let subscriptionsTask = api.subscriptions()
        async let clientsTask = api.billingClients()
        async let profitTask = api.profitability()
        async let enforcementTask = api.enforcementMode()

        do { overview = try await overviewTask } catch { fatalError = APIError.wrap(error) }
        do { invoices = try await invoicesTask } catch { degraded.append("Invoices") }
        do { subscriptions = try await subscriptionsTask } catch { degraded.append("Subscriptions") }
        do { clients = try await clientsTask } catch { degraded.append("Clients") }
        do { profitability = try await profitTask } catch { degraded.append("Profitability") }
        do { enforcement = try await enforcementTask } catch { degraded.append("Enforcement") }

        degradedSections = degraded
    }

    func setEnforcement(_ mode: EnforcementMode.Known) async {
        await runner.run("enforcement", success: "Enforcement set to \(mode.title).") { [self] in
            try await api.setEnforcementMode(mode)
        } onSuccess: { [self] in await load() }
    }

    func pay(_ invoice: Invoice,
             amountMinorUnits: Int,
             method: OrchestratorAPI.PaymentMethod,
             reference: String,
             note: String) async {
        let isFull = amountMinorUnits >= invoice.outstanding
        await runner.run("pay-\(invoice.id)") { [self] in
            let response = try await api.payInvoice(
                invoice.id,
                amountMinorUnits: amountMinorUnits,
                method: method,
                reference: reference,
                note: note
            )
            runner.successMessage = response.restored == true
                ? "Payment recorded — site restored."
                : (isFull ? "Payment recorded." : "Partial payment recorded.")
        } onSuccess: { [self] in await load() }
    }

    func void(_ invoice: Invoice) async {
        await runner.run("void-\(invoice.id)", success: "\(invoice.number ?? "Invoice") voided.") { [self] in
            try await api.voidInvoice(invoice.id)
        } onSuccess: { [self] in await load() }
    }
}

struct BillingView: View {
    /// `true` when pushed onto an existing navigation stack, so it must not create its own.
    var embedded = false

    @State private var model = BillingViewModel()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        if embedded {
            screen
        } else {
            NavigationStack { screen }
        }
    }

    private var screen: some View {
        Group {
                if let error = model.fatalError, !model.hasLoadedOnce {
                    ErrorStateView(error: error) { Task { await model.load() } }
                } else if !model.hasLoadedOnce {
                    LoadingStateView()
                } else {
                    content
                }
            }
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(embedded ? .inline : .large)
        .refreshable { await model.load() }
        .task { if !model.hasLoadedOnce { await model.load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.degradedSections.isEmpty {
                    InlineErrorBanner(message: "Could not load: \(model.degradedSections.joined(separator: ", ")).")
                }
                ActionFeedbackView(runner: model.runner)
                if let overview = model.overview { summaryCard(overview) }
                enforcementCard
                invoicesCard
                subscriptionsCard
                if !model.profitability.isEmpty { profitabilityCard }
                clientsCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func summaryCard(_ overview: BillingOverview) -> some View {
        SectionCard("This month", systemImage: "chart.pie") {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricTile(title: "MRR", value: Money.string(overview.mrr, currency: overview.currencyCode),
                               caption: "\(overview.subscriptions ?? 0) subscriptions")
                    MetricTile(title: "Outstanding", value: Money.string(overview.outstanding, currency: overview.currencyCode),
                               caption: "\(model.openInvoices.count) open invoices",
                               tone: (overview.outstanding ?? 0) > 0 ? .warning : .good)
                    MetricTile(title: "Suspended", value: "\(overview.suspended ?? 0)", caption: "sites",
                               tone: (overview.suspended ?? 0) > 0 ? .critical : .good)
                    MetricTile(title: "Past due", value: "\(overview.pastDue ?? 0)", caption: "sites",
                               tone: (overview.pastDue ?? 0) > 0 ? .warning : .good)
                }

                if let aging = overview.aging, (aging.total ?? 0) > 0 {
                    Divider()
                    VStack(spacing: 6) {
                        agingRow("Current", aging.current, tone: .good)
                        agingRow("1–30 days", aging.d1_30, tone: .warning)
                        agingRow("31–60 days", aging.d31_60, tone: .warning)
                        agingRow("61+ days", aging.d61_plus, tone: .critical)
                    }
                }
            }
        }
    }

    private func agingRow(_ label: String, _ amount: Int?, tone: StatusTone) -> some View {
        HStack {
            StatusDot(tone: tone, size: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Money.string(amount, currency: model.currencyCode))
                .font(.caption.monospacedDigit())
        }
    }

    private var enforcementCard: some View {
        SectionCard("Enforcement", systemImage: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Mode", selection: Binding(
                    get: { model.enforcement?.known ?? .off },
                    set: { mode in Task { await model.setEnforcement(mode) } }
                )) {
                    ForEach(EnforcementMode.Known.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.runner.isRunning)

                Text((model.enforcement?.known ?? .off).explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if (model.enforcement?.known ?? .off) == .on {
                    Label("Overdue sites can be suspended automatically.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var invoicesCard: some View {
        SectionCard(
            "Invoices",
            systemImage: "doc.text",
            accessory: AnyView(
                NavigationLink("All \(model.invoices.count)") {
                    InvoicesView(model: model)
                }
                .font(.footnote)
            )
        ) {
            let shown = model.openInvoices.isEmpty ? Array(model.invoices.prefix(4)) : Array(model.openInvoices.prefix(4))
            if shown.isEmpty {
                Text("No invoices yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { invoice in
                        NavigationLink {
                            InvoiceDetailView(invoice: invoice, model: model)
                        } label: {
                            InvoiceRow(invoice: invoice)
                        }
                        .buttonStyle(.plain)
                        if invoice.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var subscriptionsCard: some View {
        SectionCard("Subscriptions", systemImage: "arrow.triangle.2.circlepath") {
            if model.subscriptions.isEmpty {
                Text("No subscriptions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.subscriptions) { subscription in
                        HStack {
                            StatusDot(tone: subscription.tone)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subscription.site?.domain ?? "Site \(subscription.siteId ?? 0)")
                                    .font(.callout)
                                Text("\(subscription.client?.name ?? "—") · \(subscription.intervalLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money.string(subscription.amount, currency: subscription.currencyCode))
                                    .font(.caption.monospacedDigit())
                                if let next = subscription.nextInvoiceAt {
                                    Text("next \(next.shortDate)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var profitabilityCard: some View {
        SectionCard("Profitability", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(spacing: 10) {
                ForEach(model.profitability) { row in
                    HStack {
                        StatusDot(tone: row.tone)
                        Text(row.domain ?? "—")
                            .font(.callout)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.string(row.margin, currency: row.currencyCode))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(row.tone.color)
                            Text("\(Money.string(row.price, currency: row.currencyCode)) − \(Money.string(row.cost, currency: row.currencyCode))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var clientsCard: some View {
        SectionCard("Clients", systemImage: "person.2") {
            if model.clients.isEmpty {
                Text("No clients.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.clients) { client in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.name)
                                    .font(.callout)
                                Text(client.email ?? client.phone ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let outstanding = client.outstanding, outstanding > 0 {
                                Text(Money.string(outstanding, currency: client.currencyCode))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.orange)
                            } else {
                                Text("settled")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct InvoiceRow: View {
    var invoice: Invoice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.number ?? "Invoice \(invoice.id)")
                    .font(.callout.weight(.medium))
                Text(invoice.site?.domain ?? invoice.client?.name ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.string(invoice.amount, currency: invoice.currencyCode))
                    .font(.callout.monospacedDigit())
                StatusBadge(status: invoice.isOverdue ? "overdue" : invoice.status, tone: invoice.tone)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct InvoicesView: View {
    let model: BillingViewModel

    var body: some View {
        List {
            ForEach(model.invoices) { invoice in
                NavigationLink {
                    InvoiceDetailView(invoice: invoice, model: model)
                } label: {
                    InvoiceRow(invoice: invoice)
                }
            }
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
    }
}

struct InvoiceDetailView: View {
    let invoice: Invoice
    let model: BillingViewModel

    @State private var confirmation: Kind?
    @State private var showsPaymentSheet = false

    enum Kind: String, Identifiable {
        case void
        var id: String { rawValue }
    }

    /// Re-read from the view model so the screen reflects the state after an action.
    private var current: Invoice { model.invoices.first { $0.id == invoice.id } ?? invoice }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ActionFeedbackView(runner: model.runner)

                SectionCard(
                    current.number ?? "Invoice \(current.id)",
                    systemImage: "doc.text",
                    accessory: AnyView(StatusBadge(status: current.isOverdue ? "overdue" : current.status, tone: current.tone))
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Client", value: current.client?.name)
                        DetailRow(label: "Site", value: current.site?.domain)
                        DetailRow(label: "Period", value: periodText)
                        DetailRow(label: "Issued", value: current.issuedAt.shortDateTimeOrDash)
                        DetailRow(label: "Due", value: current.dueDate?.shortDate ?? "—")
                        Divider()
                        DetailRow(label: "Amount", value: Money.string(current.amount, currency: current.currencyCode))
                        DetailRow(label: "Paid", value: Money.string(current.amountPaid, currency: current.currencyCode))
                        DetailRow(label: "Balance", value: Money.string(current.outstanding, currency: current.currencyCode))
                        if let paidAt = current.paidAt {
                            DetailRow(label: "Paid at", value: paidAt.shortDateTime)
                        }
                    }
                }

                if !current.items.isEmpty {
                    SectionCard("Line items", systemImage: "list.bullet") {
                        VStack(spacing: 10) {
                            ForEach(Array(current.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.description ?? "—")
                                            .font(.callout)
                                        if let start = item.periodStart, let end = item.periodEnd {
                                            Text("\(start.shortDate) – \(end.shortDate)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(Money.string(item.amount, currency: item.currency ?? current.currencyCode))
                                        .font(.callout.monospacedDigit())
                                }
                            }
                        }
                    }
                }

                if current.isOpen {
                    SectionCard("Actions", systemImage: "hand.tap") {
                        VStack(spacing: 10) {
                            Button {
                                showsPaymentSheet = true
                            } label: {
                                Label("Record payment", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(role: .destructive) {
                                confirmation = .void
                            } label: {
                                Label("Void invoice", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(model.runner.isRunning)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(current.number ?? "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPaymentSheet) {
            RecordPaymentView(invoice: current, model: model)
        }
        .confirmationDialog(
            "Void this invoice?",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Void invoice", role: .destructive) { Task { await model.void(current) } }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text("A voided invoice is not collectable and stops counting toward the outstanding balance.")
        }
    }

    private var periodText: String {
        guard let start = current.periodStart, let end = current.periodEnd else { return "—" }
        return "\(start.shortDate) – \(end.shortDate)"
    }
}


/// Mirrors the panel's own payment dialog: an amount in major units, a method, and
/// optional reference/note. Paying less than the balance records a partial payment.
struct RecordPaymentView: View {
    let invoice: Invoice
    let model: BillingViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var method: OrchestratorAPI.PaymentMethod = .cash
    @State private var reference = ""
    @State private var note = ""

    private var amountMinorUnits: Int {
        let normalised = amountText.replacingOccurrences(of: ",", with: ".")
        return Int(((Double(normalised) ?? 0) * 100).rounded())
    }

    private var isFullPayment: Bool { amountMinorUnits >= invoice.outstanding }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Balance due", value: Money.string(invoice.outstanding, currency: invoice.currencyCode))
                    HStack {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.callout.monospacedDigit())
                        Text(invoice.currencyCode)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Amount received")
                } footer: {
                    if amountMinorUnits > 0 && !isFullPayment {
                        Text("Less than the balance — this records a partial payment and leaves the invoice open.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Method") {
                    Picker("Method", selection: $method) {
                        ForEach(OrchestratorAPI.PaymentMethod.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Reference (optional)", text: $reference)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Button(isFullPayment ? "Mark fully paid" : "Record partial payment") {
                        Task {
                            await model.pay(invoice,
                                            amountMinorUnits: amountMinorUnits,
                                            method: method,
                                            reference: reference,
                                            note: note)
                            dismiss()
                        }
                    }
                    .disabled(amountMinorUnits <= 0 || model.runner.isRunning)
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                amountText = String(format: "%.2f", Double(invoice.outstanding) / 100)
            }
        }
    }
}
