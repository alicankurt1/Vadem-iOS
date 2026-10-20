import Foundation
import Testing
import VademCore
import VademTestSupport

// Kodlanmış bir değerin JSON'unda tek alanı değiştirip yeniden çözmek için.
// Alan adları özellik adlarıyla aynı kabul edilir (issue'daki alanlar).
func decodeAfterReplacing<T: Codable>(_ key: String, with value: Any, in original: T) throws -> T {
    let data = try JSONEncoder().encode(original)
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object[key] = value
    let changed = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(T.self, from: changed)
}

// Derleme zamanı konformans kontrolü: tür bu kısıtları sağlamazsa derlenmez.
func requiresItemConformances<T: Sendable & Hashable & Codable & Identifiable>(_: T.Type) -> Bool
where T.ID == UUID {
    true
}
