import Foundation

/// File manager. Every signature here was read off the panel's own client, including the
/// distinction between routes that take `paths: [String]` and those that take a single
/// `path: String` — getting that backwards is a silent 400.
extension OrchestratorAPI {

    // MARK: Reading

    enum FileSort: String, Sendable, CaseIterable, Identifiable {
        case name, size, modified

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    func files(siteID: Int,
               path: String,
               showHidden: Bool = false,
               sort: FileSort = .name,
               ascending: Bool = true) async throws -> FileListing {
        var query = [URLQueryItem(name: "path", value: path)]
        if showHidden { query.append(URLQueryItem(name: "hidden", value: "1")) }
        query.append(URLQueryItem(name: "sort", value: sort.rawValue))
        query.append(URLQueryItem(name: "order", value: ascending ? "asc" : "desc"))
        return try await client.get("/sites/\(siteID)/files", query: query)
    }

    func readFile(siteID: Int, path: String) async throws -> FileReadResponse {
        try await client.get("/sites/\(siteID)/files/read", query: [URLQueryItem(name: "path", value: path)])
    }

    func fileProperties(siteID: Int, path: String) async throws -> FileProperties {
        try await client.get("/sites/\(siteID)/files/properties", query: [URLQueryItem(name: "path", value: path)])
    }

    func searchFiles(siteID: Int, path: String, query text: String, type: String? = nil) async throws -> FileListing {
        var query = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "q", value: text)]
        if let type, !type.isEmpty { query.append(URLQueryItem(name: "type", value: type)) }
        return try await client.get("/sites/\(siteID)/files/search", query: query)
    }

    func downloadFile(siteID: Int, path: String) async throws -> (Data, String?) {
        try await client.download("/sites/\(siteID)/files/download", query: [URLQueryItem(name: "path", value: path)])
    }

    // MARK: Writing

    private struct PathBody: Encodable, Sendable { var path: String }
    private struct PathsBody: Encodable, Sendable { var paths: [String] }
    private struct WriteBody: Encodable, Sendable { var path: String; var content: String }
    private struct RenameBody: Encodable, Sendable { var from: String; var to: String }
    private struct PathsDestBody: Encodable, Sendable { var paths: [String]; var dest: String }
    private struct PathDestBody: Encodable, Sendable { var path: String; var dest: String }
    private struct ChmodBody: Encodable, Sendable { var paths: [String]; var mode: String; var recursive: Bool }
    private struct ChownBody: Encodable, Sendable { var paths: [String]; var owner: String; var group: String; var recursive: Bool }

    @discardableResult
    func writeFile(siteID: Int, path: String, content: String) async throws -> Data {
        try await client.send(.put, "/sites/\(siteID)/files/write", body: WriteBody(path: path, content: content))
    }

    @discardableResult
    func makeDirectory(siteID: Int, path: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/mkdir", body: PathBody(path: path))
    }

    @discardableResult
    func touchFile(siteID: Int, path: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/touch", body: PathBody(path: path))
    }

    /// `DELETE` **with a body** — `{ paths: [...] }`.
    @discardableResult
    func deleteFiles(siteID: Int, paths: [String]) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/files/delete", body: PathsBody(paths: paths))
    }

    @discardableResult
    func renameFile(siteID: Int, from: String, to: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/rename", body: RenameBody(from: from, to: to))
    }

    @discardableResult
    func copyFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/copy", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    func moveFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/move", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    func zipFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/zip", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    func unzipFile(siteID: Int, path: String, destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/unzip", body: PathDestBody(path: path, dest: destination))
    }

    @discardableResult
    func tarFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/tar", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    func untarFile(siteID: Int, path: String, destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/untar", body: PathDestBody(path: path, dest: destination))
    }

    @discardableResult
    func chmod(siteID: Int, paths: [String], mode: String, recursive: Bool) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/chmod",
                              body: ChmodBody(paths: paths, mode: mode, recursive: recursive))
    }

    @discardableResult
    func chown(siteID: Int, paths: [String], owner: String, group: String, recursive: Bool) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/chown",
                              body: ChownBody(paths: paths, owner: owner, group: group, recursive: recursive))
    }
}
