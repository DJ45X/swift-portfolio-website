import Argon2Swift
import Foundation
import Vapor

/// A custom Vapor `PasswordHasher` backed by Argon2id, replacing Vapor's
/// default Bcrypt. Registered in `configure` via `app.passwords.use`.
///
/// Parameters follow OWASP guidance for Argon2id (≈19 MiB, 2 iterations). Since
/// the encoded hash embeds these parameters, verification stays valid even if
/// they are tuned later.
struct Argon2PasswordHasher: PasswordHasher {
    /// Time cost (number of passes).
    var iterations: Int = 2
    /// Memory cost in KiB (19456 KiB ≈ 19 MiB).
    var memory: Int = 19_456
    /// Number of parallel lanes.
    var parallelism: Int = 1
    /// Raw hash output length in bytes.
    var length: Int = 32

    func hash<Password>(_ password: Password) throws -> [UInt8]
    where Password: DataProtocol {
        let plaintext = String(decoding: password, as: UTF8.self)
        return Array(try hashToString(plaintext).utf8)
    }

    func verify<Password, Digest>(_ password: Password, created digest: Digest) throws -> Bool
    where Password: DataProtocol, Digest: DataProtocol {
        let plaintext = String(decoding: password, as: UTF8.self)
        let encoded = String(decoding: digest, as: UTF8.self)
        return try Argon2Swift.verifyHashString(password: plaintext, hash: encoded, type: .id)
    }

    /// Convenience that returns the encoded Argon2id string (`$argon2id$...`).
    func hashToString(_ password: String) throws -> String {
        let salt = Salt.newSalt()
        let result = try Argon2Swift.hashPasswordString(
            password: password,
            salt: salt,
            iterations: iterations,
            memory: memory,
            parallelism: parallelism,
            length: length,
            type: .id
        )
        return result.encodedString()
    }
}
