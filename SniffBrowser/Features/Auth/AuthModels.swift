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

/// 用户中心展示的真实资料数量快照。
///
/// 由下载、文件、收藏和历史仓库在外部汇总后注入；未接入仓库时明确显示 0，
/// 不使用示例数据代替真实状态。
struct UserCenterCounts: Equatable, Sendable {
    let downloads: Int
    let files: Int
    let favorites: Int
    let history: Int

    init(
        downloads: Int = 0,
        files: Int = 0,
        favorites: Int = 0,
        history: Int = 0
    ) {
        self.downloads = max(0, downloads)
        self.files = max(0, files)
        self.favorites = max(0, favorites)
        self.history = max(0, history)
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
