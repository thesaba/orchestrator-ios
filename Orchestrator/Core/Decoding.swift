import Foundation

/// The API sends `null` for several boolean columns that are conceptually `false`
/// (older rows missing newer flags, nullable counters). Rather than making every flag
/// optional and unwrapping at 200 call sites, a missing or null Bool decodes as `false`
/// across the whole module.
///
/// Type mismatches still throw — only absence is forgiven.
extension KeyedDecodingContainer {
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try decodeIfPresent(Bool.self, forKey: key) ?? false
    }
}
