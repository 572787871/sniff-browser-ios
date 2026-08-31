import Combine
import SwiftUI
import UIKit

final class LoginViewController: BaseViewController {
    var onAuthenticated: ((AuthSession) -> Void)?
    private let store: LoginSwiftUIStore

    init(provider: AuthProviding? = nil) {
        store = LoginSwiftUIStore(provider: provider)
        super.init(title: "账户", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(
            LoginSwiftUIScreen(
                store: store,
                onAuthenticated: { [weak self] session in
                    self?.onAuthenticated?(session)
                }
            ),
            in: contentView
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            store.cancel()
        }
    }
}

@MainActor
private final class LoginSwiftUIStore: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "登录"
        case signUp = "注册"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var status: String?
    @Published var statusIsError = false
    @Published var isLoading = false

    let isConfigured: Bool
    private let provider: AuthProviding?
    private var task: Task<Void, Never>?

    init(provider: AuthProviding?) {
        self.provider = provider
        isConfigured = provider != nil
        if provider == nil {
            status = "当前未配置 Supabase，浏览器将继续以游客模式正常使用。"
        }
    }

    func authenticate(onSuccess: @escaping (AuthSession) -> Void) {
        guard let provider else {
            show("登录服务尚未配置，当前可继续使用游客模式。")
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), !password.isEmpty else {
            show("请输入有效邮箱和密码。", isError: true)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        task?.cancel()
        isLoading = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session: AuthSession
                if mode == .signUp {
                    session = try await provider.signUp(
                        email: trimmedEmail,
                        password: password
                    )
                } else {
                    session = try await provider.signIn(
                        email: trimmedEmail,
                        password: password
                    )
                }
                guard !Task.isCancelled else { return }
                isLoading = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSuccess(session)
            } catch is CancellationError {
                return
            } catch {
                isLoading = false
                show("登录未完成，请检查网络或账户信息后重试。", isError: true)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    func requestPasswordReset() {
        guard let provider else {
            show("密码重置服务尚未配置。")
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            show("请先输入用于重置密码的邮箱。", isError: true)
            return
        }
        task?.cancel()
        isLoading = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await provider.requestPasswordReset(email: trimmedEmail)
                guard !Task.isCancelled else { return }
                isLoading = false
                show("重置邮件已发送，请检查邮箱。")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return
            } catch {
                isLoading = false
                show("暂时无法发送重置邮件，请稍后重试。", isError: true)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func show(_ value: String, isError: Bool = false) {
        status = value
        statusIsError = isError
    }
}

private struct LoginSwiftUIScreen: View {
    @ObservedObject var store: LoginSwiftUIStore
    let onAuthenticated: (AuthSession) -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    form
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(AppSwiftUIColors.secondaryText)
                .frame(width: 72, height: 72)
            Text(store.mode == .signUp ? "创建账户" : "欢迎回来")
                .font(.title2.weight(.bold))
            Text(store.mode == .signUp
                 ? "使用邮箱创建账户；认证服务会向邮箱发送验证信息。"
                 : "登录后可同步收藏、历史记录和下载记录。")
                .font(.subheadline)
                .foregroundStyle(AppSwiftUIColors.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: 16) {
            Picker("账户操作", selection: $store.mode) {
                ForEach(LoginSwiftUIStore.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isLoading)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .foregroundStyle(AppSwiftUIColors.secondaryText)
                    TextField("邮箱", text: $store.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)

                AppSwiftUIDivider(leading: 42)

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(AppSwiftUIColors.secondaryText)
                    SecureField("密码", text: $store.password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
            }
            .background(AppSwiftUIColors.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

            if let status = store.status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(
                        store.statusIsError
                            ? AppSwiftUIColors.danger
                            : AppSwiftUIColors.secondaryText
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if store.isLoading {
                        ProgressView()
                            .tint(AppSwiftUIColors.accentContent)
                    }
                    Text(store.mode == .signUp ? "注册" : "登录")
                }
            }
            .buttonStyle(AppSwiftUIPrimaryButtonStyle())
            .disabled(store.isLoading)

            if store.mode == .signIn {
                Button("忘记密码") {
                    focusedField = nil
                    store.requestPasswordReset()
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(store.isLoading)
            }
        }
        .padding(18)
        .background(AppSwiftUIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
    }

    private func submit() {
        focusedField = nil
        store.authenticate(onSuccess: onAuthenticated)
    }
}
