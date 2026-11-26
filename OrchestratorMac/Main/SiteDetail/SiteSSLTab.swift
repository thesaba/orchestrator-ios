import OrchestratorKit
import SwiftUI

/// The certificate: days left, issuer and expiry, renew or issue, and every host name with
/// whether the certificate covers it.
struct SiteSSLTab: View {
    let environment: AppEnvironment
    var row: SiteTableRow

    @State private var ssl: SiteSSL?
    @State private var hosts: SSLHosts?
    @State private var error: String?

    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusDangerText)
                }
                certificateCard
                hostsCard
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task(id: row.id) { await load() }
    }

    private func load() async {
        async let certificate = try? environment.api.siteSSL(siteID: row.id)
        async let names = try? environment.api.sslHosts(siteID: row.id)
        ssl = await certificate
        hosts = await names
        error = ssl == nil && hosts == nil ? "Could not read the certificate of \(row.domain)." : nil
    }

    // MARK: - Certificate

    private var certificateCard: some View {
        HStack(spacing: 20) {
            DaysRing(days: ssl?.daysLeft, active: ssl?.active ?? false)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                if ssl?.running == true || hosts?.running == true {
                    Label("Certbot is running for this site", systemImage: "hourglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Check Again") { Task { await load() } }
            if ssl?.active == true {
                Button("Renew…") {
                    let id = row.id
                    Task { await executor.renewCertificate(siteID: id) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Issue Certificate…") {
                    let id = row.id
                    Task { await executor.issueCertificate(siteID: id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(ssl == nil)
            }
        }
        .padding(16)
        .card()
    }

    private var headline: String {
        guard let ssl else { return "Reading the certificate…" }
        guard ssl.active else { return "No certificate" }
        if let days = ssl.daysLeft, days <= AppSettings.sslWarningDays { return "Certificate expires soon" }
        return "Certificate is valid"
    }

    private var detail: String {
        guard let ssl else { return " " }
        guard ssl.active else { return ssl.sslEnabled ? "HTTPS is on but no certificate was found." : "HTTPS is off for \(row.domain)." }
        var parts: [String] = []
        if let issuer = ssl.issuer { parts.append(issuer) }
        if let expires = ssl.expiresAt { parts.append("expires \(expires.formatted(date: .long, time: .omitted))") }
        parts.append("certbot renews automatically before expiry")
        return parts.joined(separator: " · ")
    }

    // MARK: - Hosts

    private var hostsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Host names")
            if let hosts {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Host").frame(maxWidth: .infinity, alignment: .leading)
                        Text("DNS").frame(width: 70)
                        Text("Nginx").frame(width: 70)
                        Text("HTTPS").frame(width: 70)
                        Text("Certificate").frame(width: 110, alignment: .trailing)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    // An active certificate that covers none of the names means the panel could
                    // not read its name list, not that nothing is covered.
                    let coverageKnown = !hosts.certActive || hosts.hosts.contains(where: \.covered)
                    ForEach(hosts.hosts) { host in
                        Divider()
                        HostRow(host: host, coverageKnown: coverageKnown)
                    }
                }
                .card()
                Text("A host name is covered once its DNS points to this server and it is listed in the site’s nginx config; issue the certificate again after adding one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}

private struct HostRow: View {
    var host: SSLHosts.Host
    var coverageKnown: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(host.host).font(.system(size: 13, weight: host.primary ? .semibold : .regular))
                if host.primary { Tag(text: "Primary") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            check(host.dns, "DNS").frame(width: 70)
            check(host.inNginx, "In nginx").frame(width: 70)
            check(host.https, "HTTPS").frame(width: 70)
            Text(coverageKnown ? (host.covered ? "Covered" : "Not covered") : "Unknown")
                .font(.system(size: 12))
                .foregroundStyle(!coverageKnown ? Color.secondary : (host.covered ? Color.statusSuccessText : Color.statusWarningText))
                .frame(width: 110, alignment: .trailing)
                .help(coverageKnown ? "" : "The panel could not read the names on the certificate")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    private func check(_ ok: Bool, _ label: String) -> some View {
        Image(systemName: ok ? "checkmark" : "minus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(ok ? Color.statusSuccess : Color.secondary)
            .accessibilityLabel("\(label): \(ok ? "yes" : "no")")
    }
}

/// Days left on a 90-day certificate as a ring.
private struct DaysRing: View {
    var days: Int?
    var active: Bool

    var body: some View {
        let fraction = active ? min(1, max(0, Double(days ?? 0) / 90)) : 0
        let tint: Color = !active ? .secondary : ((days ?? 0) <= AppSettings.sslWarningDays ? .statusWarning : .statusSuccess)
        ZStack {
            Circle().stroke(Color.barTrack, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(active ? (days.map(String.init) ?? "—") : "—")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                Text("days left").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "\(days ?? 0) days left" : "No certificate")
    }
}
