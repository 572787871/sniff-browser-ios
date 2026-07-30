import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let id: UUID
    let email: String?
    let displayName: String?
    let createdAt: Date

    init(
        id: UUID,
        email: String?,
        displayName: String?,
        createdAt: Date
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

struct AuthSession: Codable, Equatable, Sendable {
    let user: AuthUser
    let expiresAt: Date?

    init(user: AuthUser, expiresAt: Date?) {
        self.user = user
        self.expiresAt = expiresAt
    }
}

@MainActor
protocol AuthProviding: AnyObject {
    var currentSession: AuthSession? { get }

    func restoreSession() async throws -> AuthSession?
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String) async throws -> AuthSession
    func requestPasswordReset(email: String) async throws
    func signOut() async throws
}
