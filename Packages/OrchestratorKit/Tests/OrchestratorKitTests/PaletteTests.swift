import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Fuzzy matching")
struct FuzzyMatcherTests {
    @Test func matchesVerbAndTargetPrefixesInAnyOrder() {
        #expect(FuzzyMatcher.score("dep ci", in: "deploy citynet.ge") != nil)
        #expect(FuzzyMatcher.score("ci dep", in: "deploy citynet.ge") != nil)
        #expect(FuzzyMatcher.score("dep xyz", in: "deploy citynet.ge") == nil)
    }

    @Test func prefixBeatsSubstringBeatsSubsequence() throws {
        let prefix = try #require(FuzzyMatcher.score("net", in: "deploy netflow.ge"))
        let substring = try #require(FuzzyMatcher.score("net", in: "deploy citynet.ge"))
        let subsequence = try #require(FuzzyMatcher.score("cng", in: "deploy citynet.ge"))
        #expect(prefix > substring)
        #expect(substring > subsequence)
    }

    @Test func domainPartsAreWords() {
        // "ge" is the start of a word inside "citynet.ge".
        let score = FuzzyMatcher.score("ge", in: "deploy citynet.ge") ?? 0
        #expect(score >= 10)
    }

    @Test func emptyQueryMatches() {
        #expect(FuzzyMatcher.score("   ", in: "anything") == 0)
    }
}

@Suite("Command catalog and ranking")
struct CommandCatalogTests {
    let sites = [
        SiteListing(id: 1, name: "CityNet", domain: "citynet.ge", serverId: 5, branch: "main", sslEnabled: true,
                    deployments: [DeploymentRecord(id: 9, siteId: 1, status: "success", createdAt: Fixtures.now)]),
        SiteListing(id: 2, name: "Staging", domain: "staging.citynet.ge", serverId: 5, branch: "develop",
                    maintenanceMode: true),
        SiteListing(id: 3, name: "Old", domain: "old.example", disabled: true)
    ]
    let servers = [
        FleetServer(id: 5, name: "do-fra-web-01", hasSsh: true, location: "Frankfurt"),
        FleetServer(id: 6, name: "panel", kind: "local")
    ]

    var commands: [PaletteCommand] { CommandCatalog.commands(sites: sites, servers: servers) }

    @Test func buildsSiteAndServerCommands() {
        let ids = Set(commands.map(\.id))
        #expect(ids.contains("deploy:1"))
        #expect(ids.contains("ssl:1"))
        #expect(!ids.contains("ssl:2"))           // SSL not enabled
        #expect(ids.contains("maintenance-off:2")) // already in maintenance
        #expect(ids.contains("maintenance-on:1"))
        #expect(!ids.contains("deploy:3"))         // disabled site
        #expect(ids.contains("ssh:5"))
        #expect(ids.contains("ssh:6"))             // the local server
        #expect(ids.contains("lastlog:1"))
        #expect(!ids.contains("lastlog:2"))        // no deployments yet
    }

    @Test func touchIDOnlyForRollbackAndMaintenance() {
        let flagged = Set(commands.filter(\.requiresAuthentication).map(\.id))
        #expect(flagged == ["rollback:1", "rollback:2", "maintenance-on:1", "maintenance-off:2"])
        #expect(commands.first { $0.id == "ssh:5" }?.kind.changesProduction == false)
    }

    @Test func sshDetailNamesHostedSites() {
        let ssh = commands.first { $0.id == "ssh:5" }
        #expect(ssh?.detail == "hosts citynet.ge +1 · opens Terminal")
    }

    @Test func depCiPutsDeployCitynetFirst() {
        let sections = CommandCatalog.rank(commands, query: "dep ci", recent: [])
        #expect(sections.first?.group == .actions)
        #expect(sections.first?.commands.first?.id == "deploy:1")
        #expect(sections.first?.commands.dropFirst().first?.id == "deploy:2")
    }

    @Test func recentCommandsRankHigher() {
        let plain = CommandCatalog.rank(commands, query: "deploy", recent: [])
        let boosted = CommandCatalog.rank(commands, query: "deploy", recent: ["deploy:2"])
        #expect(plain.first?.commands.first?.id == "deploy:1")
        #expect(boosted.first?.commands.first?.id == "deploy:2")
    }

    @Test func emptyQueryShowsRecentsThenActions() {
        let recents = CommandCatalog.rank(commands, query: "", recent: ["ssh:5", "missing", "deploy:1"])
        #expect(recents.map(\.group) == [.recent])
        #expect(recents.first?.commands.map(\.id) == ["ssh:5", "deploy:1"])

        let none = CommandCatalog.rank(commands, query: "", recent: [])
        #expect(none.first?.group == .actions)
        #expect(none.first?.commands.count == 8)
    }

    @Test func noResults() {
        #expect(CommandCatalog.rank(commands, query: "zzzz", recent: []).isEmpty)
    }

    @Test func recordingMovesToFrontWithoutDuplicates() {
        #expect(CommandCatalog.recording("b", in: ["a", "b", "c"]) == ["b", "a", "c"])
        #expect(CommandCatalog.recording("x", in: ["a", "b"], keep: 2) == ["x", "a"])
    }
}

@Suite("Artisan safety and action replies")
struct ActionTests {
    @Test func artisanAuthentication() {
        #expect(ArtisanSafety.needsAuthentication("migrate"))
        #expect(ArtisanSafety.needsAuthentication("migrate:fresh --seed"))
        #expect(ArtisanSafety.isDataLoss("db:wipe"))
        #expect(!ArtisanSafety.isDataLoss("migrate"))
        #expect(!ArtisanSafety.needsAuthentication("optimize:clear"))
        #expect(!ArtisanSafety.needsAuthentication("queue:restart"))
    }

    @Test func deployReplies() throws {
        let started = try Fixtures.decode(DeployStartResponse.self, #"{"started": true, "deploymentId": 91}"#)
        #expect(started.started && started.deploymentId == 91 && !started.queued)
        let queued = try Fixtures.decode(DeployStartResponse.self,
                                         #"{"queued": true, "message": "Deploy queued — will start automatically after the current one finishes."}"#)
        #expect(queued.queued && !queued.started && queued.deploymentId == nil)
    }

    @Test func explanationReplies() throws {
        let stored = try Fixtures.decode(DeployExplanation.self, #"{"explanation": null, "history": []}"#)
        #expect(stored.explanation == nil)
        let fresh = try Fixtures.decode(DeployExplanation.self,
                                        #"{"explanation": "The migration adds a column that exists.", "cached": false, "interactionId": 4, "history": []}"#)
        #expect(fresh.explanation?.hasPrefix("The migration") == true)
        // The iOS chat model reads the same reply.
        let chat = try Fixtures.decode(AIChatResponse.self, #"{"explanation": "x", "cached": true}"#)
        #expect(chat.reply == "x")
    }

    @Test func maintenanceReply() throws {
        let result = try Fixtures.decode(MaintenanceResult.self, #"{"ok": true, "action": "down", "output": "INFO  Application is now in maintenance mode."}"#)
        #expect(result.ok && result.action == "down")
    }
}
