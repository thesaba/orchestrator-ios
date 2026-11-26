import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Fleet server detail")
struct FleetDetailTests {
    @Test func actionsEncodeAsThePanelExpects() throws {
        func body(_ action: FleetAction) throws -> String {
            struct Body: Encodable { var action: String; var args: [String: JSONValue]? }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let args = action.args
            return String(decoding: try encoder.encode(Body(action: action.apiName, args: args.isEmpty ? nil : args)), as: UTF8.self)
        }
        #expect(try body(.service(.restart, name: "nginx")) == #"{"action":"service.restart","args":{"name":"nginx"}}"#)
        #expect(try body(.reboot(delayMinutes: 0)) == #"{"action":"reboot"}"#)
        #expect(try body(.reboot(delayMinutes: 5)) == #"{"action":"reboot","args":{"delayMin":5}}"#)
        #expect(try body(.updatePackages(distUpgrade: false)) == #"{"action":"packages.update","args":{"mode":"upgrade"}}"#)
        #expect(try body(.container(.restart, id: "abc123", name: "n8n")) == #"{"action":"docker.restart","args":{"id":"abc123"}}"#)
        #expect(FleetAction.service(.stop, name: "mysql").isDestructive)
        #expect(!FleetAction.service(.restart, name: "mysql").isDestructive)
        #expect(FleetAction.reboot(delayMinutes: 0).isDestructive)
    }

    @Test func inventoryAndRunDecode() throws {
        let inventory = #"""
        {"inventory":{"services":[{"name":"nginx","description":"A high performance web server","active":"active","sub":"running","enabled":"enabled"},
          {"name":"mysql","description":"MySQL","active":"failed","sub":"failed","enabled":"enabled"}],
          "failedUnits":["mysql.service"],"docker":{"available":true,"containers":[{"id":"abc","name":"n8n","image":"n8nio/n8n","state":"running","status":"Up 14 days","cpu":1.2,"memBytes":200000000}]},
          "updates":{"manager":"apt","count":6,"security":2,"rebootRequired":true,"packages":[{"name":"openssl","current":"3.0.13","available":"3.0.14","security":true}]},
          "os":"Ubuntu 24.04","kernel":"6.8.0","hostname":"web-01","timezone":"UTC"},
         "at":"2026-11-25T12:00:00.000Z","channel":"agent"}
        """#
        let response = try Fixtures.decode(FleetInventoryResponse.self, inventory)
        #expect(response.inventory?.services.filter(\.isFailed).map(\.name) == ["mysql"])
        #expect(response.inventory?.updates?.security == 2)
        #expect(response.inventory?.docker?.containers.first?.name == "n8n")
        #expect(try Fixtures.decode(FleetInventoryResponse.self, #"{"inventory":null,"at":null,"channel":"none"}"#).inventory == nil)

        let run = #"{"id":7,"kind":"action","command":"service.restart name=nginx","createdAt":"2026-11-25T12:00:00.000Z","finishedAt":null,"targets":[{"id":1,"serverId":3,"serverName":"web","status":"success","channel":"agent","exitCode":0,"output":"ok","startedAt":null,"finishedAt":null}]}"#
        let decoded = try Fixtures.decode(FleetRun.self, run)
        #expect(decoded.isFinished)
        #expect(decoded.targets.first?.output == "ok")

        let forecast = try Fixtures.decode(FleetForecast.self, #"{"mounts":[{"mount":"/","usedPct":91.2,"daysLeft":9.4},{"mount":"/boot","usedPct":40,"daysLeft":null}]}"#)
        #expect(forecast.mounts.first?.daysLeft == 9.4)

        let processes = try Fixtures.decode(FleetProcesses.self, #"{"processes":[{"pid":12,"user":"mysql","name":"mysqld","cmd":"/usr/sbin/mysqld","cpu":14.2,"mem":51.0,"rss":4100000000}],"channel":"agent"}"#)
        #expect(processes.processes.first?.name == "mysqld")
    }
}
