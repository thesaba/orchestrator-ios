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
