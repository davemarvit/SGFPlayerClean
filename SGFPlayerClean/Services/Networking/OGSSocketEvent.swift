import Foundation

/// The event envelope after Socket.IO framing has been removed.
/// Keep array payloads intact: lobby batches are not dictionaries.
struct OGSSocketEvent {
    let name: String
    let payload: Any?

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let name = values.first as? String, !name.isEmpty else { return nil }
        self.name = name
        payload = values.count > 1 ? values[1] : nil
    }

    var object: [String: Any] { payload as? [String: Any] ?? [:] }

    var containerData: Data? {
        guard let payload, JSONSerialization.isValidJSONObject(payload) else { return nil }
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
