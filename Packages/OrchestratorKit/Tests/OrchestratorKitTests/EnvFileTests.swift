import Foundation
import Testing
@testable import OrchestratorKit

@Suite(".env display and diff")
struct EnvFileTests {
    let sample = """
    # Application
    APP_NAME="City Net"
    APP_ENV=production
    APP_KEY=base64:abcdefghijklmnop
    APP_URL=https://citynet.ge # public URL

    DB_HOST=127.0.0.1
    DB_PASSWORD='s3cr#t'
    export QUEUE_CONNECTION=sync
    SENTRY_LARAVEL_DSN=https://key@sentry.io/1
    not a variable
    APP_ENV=staging
    """

    @Test func parsesValuesQuotesCommentsAndRepeats() {
        let file = EnvFile(sample)
        #expect(file.value(for: "APP_NAME") == "City Net")
        #expect(file.value(for: "APP_URL") == "https://citynet.ge")
        #expect(file.value(for: "DB_PASSWORD") == "s3cr#t")
        #expect(file.value(for: "QUEUE_CONNECTION") == "sync")
        // The later APP_ENV wins and moves to its line.
        #expect(file.value(for: "APP_ENV") == "staging")
        #expect(file.entries.map(\.key) == ["APP_NAME", "APP_KEY", "APP_URL", "DB_HOST", "DB_PASSWORD",
                                            "QUEUE_CONNECTION", "SENTRY_LARAVEL_DSN", "APP_ENV"])
    }

    @Test func recognisesAndMasksSecrets() {
        let file = EnvFile(sample)
        let secrets = file.entries.filter(\.isSecret).map(\.key)
        #expect(secrets == ["APP_KEY", "DB_PASSWORD", "SENTRY_LARAVEL_DSN"])
        #expect(file.entries.first { $0.key == "DB_PASSWORD" }?.maskedValue == "••••••••")
        #expect(file.entries.first { $0.key == "APP_URL" }?.maskedValue == "https://citynet.ge")
        #expect(!EnvFile.isSecret(key: "APP_DEBUG"))
        #expect(EnvFile.isSecret(key: "aws_secret_access_key"))
    }

    @Test func groupsByPrefixWithSinglesInOther() {
        let groups = EnvFile(sample).groups
        #expect(groups.map(\.name) == ["APP", "DB", "Other"])
        #expect(groups[2].entries.map(\.key) == ["QUEUE_CONNECTION", "SENTRY_LARAVEL_DSN"])
    }

    @Test func diffNamesKeysNotValues() {
        let old = "APP_ENV=production\nQUEUE_CONNECTION=sync\nDEBUGBAR=true\nDB_PASSWORD=a"
        let new = "APP_ENV=production\nQUEUE_CONNECTION=redis\nDB_PASSWORD=b\nSENTRY_TRACES_SAMPLE_RATE=0.2"
        let changes = EnvChange.between(old, new)
        #expect(changes.map(\.summary) == ["~ QUEUE_CONNECTION", "~ DB_PASSWORD", "+ SENTRY_TRACES_SAMPLE_RATE", "− DEBUGBAR"])
        #expect(changes.first { $0.key == "DB_PASSWORD" }?.isSecret == true)
        #expect(EnvChange.between(old, old).isEmpty)
    }

    @Test func sslHostsDecode() throws {
        let json = #"{"certActive":true,"certName":"a.example","running":false,"hosts":[{"host":"a.example","primary":true,"inNginx":true,"https":true,"cert":"a.example","covered":true,"dns":true},{"host":"www.a.example","primary":false,"inNginx":true,"https":false,"cert":null,"covered":false,"dns":false}]}"#
        let hosts = try Fixtures.decode(SSLHosts.self, json)
        #expect(hosts.hosts.map(\.host) == ["a.example", "www.a.example"])
        #expect(hosts.hosts[1].covered == false)
        #expect(hosts.hosts[0].cert == "a.example")
    }
}
