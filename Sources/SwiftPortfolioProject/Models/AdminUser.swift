import Argon2Swift
import Fluent
import Vapor
import struct Foundation.UUID
import struct Foundation.Date

/// The single privileged user who can publish journal entries.
final class AdminUser: Model, @unchecked Sendable {
    static let schema = "admin_users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    /// Argon2id-encoded password hash (the full `$argon2id$v=19$...` string).
    @Field(key: "password_hash")
    var passwordHash: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(id: UUID? = nil, username: String, passwordHash: String) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
    }
}

// MARK: - Authentication

extension AdminUser: ModelAuthenticatable {
    // Explicit (non-Sendable) KeyPath annotations: Swift 6 infers key-path
    // literals as `KeyPath & Sendable`, which doesn't match the protocol's
    // plain `KeyPath<Self, FieldProperty<Self, String>>` requirement.
    static let usernameKey: KeyPath<AdminUser, FieldProperty<AdminUser, String>> = \AdminUser.$username
    static let passwordHashKey: KeyPath<AdminUser, FieldProperty<AdminUser, String>> = \AdminUser.$passwordHash

    /// Verifies a plaintext password against the stored Argon2id hash. The hash
    /// parameters (memory/iterations/salt) are read from the encoded string, so
    /// this keeps working even if hashing parameters change later.
    func verify(password: String) throws -> Bool {
        try Argon2Swift.verifyHashString(password: password, hash: self.passwordHash, type: .id)
    }
}

extension AdminUser: ModelSessionAuthenticatable { }
extension AdminUser: ModelCredentialsAuthenticatable { }
