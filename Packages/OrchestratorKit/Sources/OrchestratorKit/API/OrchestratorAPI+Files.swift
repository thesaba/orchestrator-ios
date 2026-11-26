import Foundation

/// File manager. Every signature here was read off the panel's own client, including the
/// distinction between routes that take `paths: [String]` and those that take a single
/// `path: String` — getting that backwards is a silent 400.
extension OrchestratorAPI {

    // MARK: Reading

    public enum FileSort: String, Sendable, CaseIterable, Identifiable {
        case name, size, modified

        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public func files(siteID: Int,
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

    public func readFile(siteID: Int, path: String) async throws -> FileReadResponse {
        try await client.get("/sites/\(siteID)/files/read", query: [URLQueryItem(name: "path", value: path)])
    }

    public func fileProperties(siteID: Int, path: String) async throws -> FileProperties {
        try await client.get("/sites/\(siteID)/files/properties", query: [URLQueryItem(name: "path", value: path)])
    }

    public func searchFiles(siteID: Int, path: String, query text: String, type: String? = nil) async throws -> FileListing {
        var query = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "q", value: text)]
        if let type, !type.isEmpty { query.append(URLQueryItem(name: "type", value: type)) }
        return try await client.get("/sites/\(siteID)/files/search", query: query)
    }

    public func downloadFile(siteID: Int, path: String) async throws -> (Data, String?) {
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

    /// Uploads files into `destination` (a path relative to the site root).
    /// `POST /files/upload?dest=&overwrite=0|1`, multipart.
    @discardableResult
    public func uploadFiles(siteID: Int, destination: String, files: [(name: String, data: Data)], overwrite: Bool) async throws -> Data {
        try await client.upload("/sites/\(siteID)/files/upload",
                                query: [URLQueryItem(name: "dest", value: destination),
                                        URLQueryItem(name: "overwrite", value: overwrite ? "1" : "0")],
                                files: files)
    }

    @discardableResult
    public func writeFile(siteID: Int, path: String, content: String) async throws -> Data {
        try await client.send(.put, "/sites/\(siteID)/files/write", body: WriteBody(path: path, content: content))
    }

    @discardableResult
    public func makeDirectory(siteID: Int, path: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/mkdir", body: PathBody(path: path))
    }

    @discardableResult
    public func touchFile(siteID: Int, path: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/touch", body: PathBody(path: path))
    }

    /// `DELETE` **with a body** — `{ paths: [...] }`.
    @discardableResult
    public func deleteFiles(siteID: Int, paths: [String]) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/files/delete", body: PathsBody(paths: paths))
    }

    @discardableResult
    public func renameFile(siteID: Int, from: String, to: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/rename", body: RenameBody(from: from, to: to))
    }

    @discardableResult
    public func copyFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/copy", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    public func moveFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/move", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    public func zipFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/zip", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    public func unzipFile(siteID: Int, path: String, destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/unzip", body: PathDestBody(path: path, dest: destination))
    }

    @discardableResult
    public func tarFiles(siteID: Int, paths: [String], destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/tar", body: PathsDestBody(paths: paths, dest: destination))
    }

    @discardableResult
    public func untarFile(siteID: Int, path: String, destination: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/untar", body: PathDestBody(path: path, dest: destination))
    }

    @discardableResult
    public func chmod(siteID: Int, paths: [String], mode: String, recursive: Bool) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/chmod",
                              body: ChmodBody(paths: paths, mode: mode, recursive: recursive))
    }

    @discardableResult
    public func chown(siteID: Int, paths: [String], owner: String, group: String, recursive: Bool) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/files/chown",
                              body: ChownBody(paths: paths, owner: owner, group: group, recursive: recursive))
    }
}
