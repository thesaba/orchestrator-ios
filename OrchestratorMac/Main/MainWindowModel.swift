import Foundation
import Observation
import OrchestratorKit

/// What the main window shows: the sidebar selection, the toolbar search, the site table's
/// filter and selection. Lives as long as the window controller.
@MainActor
@Observable
final class MainWindowModel {
    var selection: SidebarItem? = .dashboard
    /// Typing in the toolbar search jumps to the site table, which it filters.
    var searchText = "" {
        didSet {
            if !searchText.isEmpty, oldValue.isEmpty, selection != .sites { selection = .sites }
        }
    }
    var siteFilter: SiteFilter = .all
    var selectedSiteID: Int?
    var showsInspector = true
    /// The site whose page is open under Sites; nil shows the table.
    var openSiteID: Int?
    var siteTab: SiteTab = .overview
    /// The server whose page is open under Servers; nil shows the list.
    var openServerID: Int?
    var selectedServerID: Int?

    let data: MainDataStore

    init(data: MainDataStore) {
        self.data = data
    }

    /// Shows one site in the table with its inspector open.
    func reveal(siteID: Int) {
        searchText = ""
        siteFilter = .all
        selection = .sites
        openSiteID = nil
        selectedSiteID = siteID
        showsInspector = true
    }

    /// Opens a site's page on one of its tabs.
    func openSite(_ siteID: Int, tab: SiteTab = .overview) {
        selection = .sites
        selectedSiteID = siteID
        siteTab = tab
        openSiteID = siteID
    }

    /// Opens a server's page.
    func openServer(_ serverID: Int) {
        selection = .servers
        selectedServerID = serverID
        openServerID = serverID
    }

    /// Back from a site's page to the table, keeping the site selected.
    func closeSite() {
        openSiteID = nil
    }
}
