import Foundation
import Security

/// Aster's secrets in the Keychain. A secret read once stays in memory for the rest of the launch:
/// a build signed without a team identity must ask the user before its first read of each item,
/// and the cache keeps that to one request per item instead of one per use.
enum CredentialVault {
    static let service = "com.aster.private-credentials"
    private static let lock = NSLock()
    private static var cache: [String: Data] = [:]
    static func read(_ account: String) throws -> Data? {
        if let cached = lock.withLock({ cache[account] }) { return cached }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw VaultError(status: status) }
        lock.withLock { cache[account] = data }
        return data
    }
    /// Whether a secret is saved, without reading it, so macOS never has to ask for it.
    static func contains(_ account: String) -> Bool {
        if lock.withLock({ cache[account] != nil }) { return true }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func save(_ data: Data, account: String) throws {
        defer { lock.withLock { cache[account] = nil } }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecItemNotFound {
            let status = SecItemAdd(query.merging(values) { _, value in value } as CFDictionary, nil)
            guard status == errSecSuccess else { throw VaultError(status: status) }
        } else if updated != errSecSuccess { throw VaultError(status: updated) }
    }
    static func remove(_ account: String) throws {
        lock.withLock { cache[account] = nil }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }
    struct VaultError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            // The user declined, or closed, the macOS request to let this version of Aster read the item.
            [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed].contains(status)
                ? "macOS no ha dejado a Aster leer su clave guardada. Cuando te pida la contraseña del Mac para el Llavero, escríbela y pulsa «Permitir siempre»."
                : "No se pudo acceder al Llavero (\(status)). Desbloquea tu sesión y vuelve a intentarlo."
        }
    }
}
