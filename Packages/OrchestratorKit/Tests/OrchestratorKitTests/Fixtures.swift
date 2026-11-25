import Foundation
@testable import OrchestratorKit

/// Response bodies shaped like the panel's serializers (see `apps/api/src/lib/fleet/serialize.ts`,
/// `routes/fleet.ts`, `routes/sites.ts`). Values are made up.
enum Fixtures {
    static let fleetServers = """
    {
      "servers": [
        {
          "id": 1, "name": "panel", "kind": "local", "host": null, "hasSsh": false, "sshStatus": "unknown",
          "agentStatus": "none", "agentVersion": null, "agentArch": null, "agentMode": null,
          "agentAllowTerminal": null, "agentAllowCommands": null, "agentLastSeenAt": null,
          "agentAutoUpdate": false, "agentUpdateAvailable": false, "channel": "local",
          "location": "Frankfurt", "groupName": null, "tags": [], "provider": "DigitalOcean", "notes": null,
          "preferredChannel": "auto", "latencyMs": null, "maintenanceUntil": null, "offlineAlertSecs": 0,
          "terminalEnabled": true, "commandsEnabled": true, "aiActions": [], "siteCount": 8,
          "system": {"os": "Ubuntu", "kernel": null, "hostname": "panel", "cpuModel": null, "cores": 4,
                     "memTotal": 8000000000, "bootTime": null, "capabilities": []},
          "latest": {"at": "2026-11-25T12:00:00.000Z", "source": "local",
                     "m": {"ts": 1795000000, "cpu": {"percent": 34.2, "perCore": null, "load1": 0.8, "load5": 0.6,
                           "load15": 0.5, "cores": 4, "steal": null, "iowait": null},
                           "mem": {"total": 8000000000, "used": 4880000000, "available": null, "swapTotal": 0, "swapUsed": 0},
                           "disks": [{"mount": "/boot", "fs": "ext4", "device": "sda1", "total": 1000, "used": 990,
                                      "inodesTotal": 10, "inodesUsed": 1},
                                     {"mount": "/", "fs": "ext4", "device": "sda2", "total": 100000, "used": 91000,
                                      "inodesTotal": 10, "inodesUsed": 1}],
                           "diskIO": null, "net": {"rxBps": 100, "txBps": 50, "rxTotal": 1, "txTotal": 1, "ifaces": []},
                           "uptime": 86400, "procs": 120, "tcpConns": null}},
          "activeAlerts": 1
        },
        {
          "id": 2, "name": "relay", "kind": "remote", "host": "203.0.113.5", "hasSsh": true, "sshStatus": "online",
          "agentStatus": "pending", "agentVersion": null, "agentArch": null, "agentMode": null,
          "agentAllowTerminal": null, "agentAllowCommands": null, "agentLastSeenAt": null,
          "agentAutoUpdate": true, "agentUpdateAvailable": false, "channel": "ssh",
          "location": null, "groupName": null, "tags": ["edge"], "provider": null, "notes": null,
          "preferredChannel": "auto", "latencyMs": 12, "maintenanceUntil": null, "offlineAlertSecs": 300,
          "terminalEnabled": false, "commandsEnabled": false, "aiActions": [], "siteCount": 0,
          "system": {"os": null, "kernel": null, "hostname": null, "cpuModel": null, "cores": null,
                     "memTotal": null, "bootTime": null, "capabilities": []},
          "latest": null, "activeAlerts": 0
        }
      ],
      "shippedAgentVersion": "1.4.0"
    }
    """

    static let fleetAlerts = """
    {"events": [
      {"id": 41, "serverId": 1, "serverName": "panel", "ruleId": 3, "kind": "disk",
       "message": "Disk / at 91%", "value": 91, "startedAt": "2026-11-25T11:48:00.000Z", "resolvedAt": null}
    ]}
    """

    static let sslOverview = """
    {"sites": [
      {"siteId": 10, "domain": "a.example", "daysLeft": 6, "expiresAt": "2026-12-01T10:00:00.000Z", "error": null},
      {"siteId": 11, "domain": "b.example", "daysLeft": 70, "expiresAt": "2027-02-03T10:00:00.000Z", "error": null}
    ]}
    """

    static let uptime = """
    {"sites": [
      {"siteId": 10, "domain": "a.example", "monitoring": true, "status": "up", "responseMs": 40,
       "statusCode": 200, "checkedAt": "2026-11-25T11:59:00.000Z"},
      {"siteId": 11, "domain": "b.example", "monitoring": true, "status": "down", "responseMs": null,
       "statusCode": 502, "checkedAt": "2026-11-25T11:59:00.000Z"},
      {"siteId": 12, "domain": "c.example", "monitoring": false, "status": null, "responseMs": null,
       "statusCode": null, "checkedAt": null}
    ]}
    """

    static let sites = """
    [
      {"id": 10, "name": "Alpha", "domain": "a.example", "serverId": null, "phpVersion": "8.4",
       "sslEnabled": true, "status": "active", "branch": "main", "healthCheck": true, "runTests": false,
       "testUseSqlite": true, "deployQueued": false, "maintenanceMode": false, "uptimeMonitor": true,
       "statusPageEnabled": false, "secBasicAuth": false, "pinned": false, "disabled": false,
       "tags": "[]", "createdAt": "2026-07-01T10:16:14.557Z", "updatedAt": "2026-07-07T17:18:27.985Z",
       "deployments": [{"id": 90, "siteId": 10, "commit": null, "branch": "main", "status": "running",
                        "log": "[12:00:01] === Deploying branch 'main' to /var/www/sites/a.example ===\\n[12:00:01] [1/8] Cloning repository...\\n__COMMIT_MSG__:Fix invoice rounding\\n[12:00:09] [2/8] Linking shared files...\\n[12:00:10] [3/8] Installing PHP dependencies...\\n",
                        "comment": null, "testResult": null, "testsPassed": null, "testsFailed": null,
                        "testsTotal": null, "testDurationMs": null, "createdAt": "2026-11-25T12:00:00.000Z"}],
       "hasGitToken": true, "sslDaysLeft": 6, "sslExpiresAt": "2026-12-01 10:00:00+00:00",
       "enforcementLevel": "none", "billingSuspended": false, "billingPastDue": false},
      {"id": 11, "name": "Beta", "domain": "b.example", "serverId": 2, "sslEnabled": null, "status": "active",
       "branch": "develop", "deployQueued": null, "maintenanceMode": false, "disabled": false,
       "deployments": [{"id": 80, "siteId": 11, "commit": "a41c9e2ff", "branch": "develop", "status": "success",
                        "log": null, "createdAt": "2026-11-24T18:02:00.000Z"}],
       "sslDaysLeft": 70, "billingSuspended": false},
      {"id": 12, "name": "Gamma", "domain": "c.example", "status": "active", "disabled": true, "deployments": []}
    ]
    """

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(type, from: Data(json.utf8))
    }

    static let now = DateParsing.parse("2026-11-25T12:00:30.000Z")!
}
