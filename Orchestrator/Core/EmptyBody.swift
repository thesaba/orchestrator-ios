import Foundation

/// Encodes as `{}`.
///
/// Several routes are POST/PUT with no meaningful payload, but Fastify rejects a request
/// that declares `Content-Type: application/json` and sends nothing. The panel's own
/// client works around this by posting the literal string `"{}"`.
struct EmptyBody: Encodable, Sendable {
    func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }

    private enum EmptyCodingKey: CodingKey {}
}
