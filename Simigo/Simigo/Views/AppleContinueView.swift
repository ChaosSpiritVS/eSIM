import SwiftUI

struct AppleContinueView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var navBridge: NavigationBridge
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var bannerCenter: BannerCenter
    private var repo: UserRepositoryProtocol { AppConfig.isMock ? MockUserRepository(auth: auth) : HTTPUserRepository() }

    let prefillName: String?
    let prefillLastName: String?

    @State private var name: String = ""
    @State private var lastName: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var showErrorBanner = false

    init(prefillName: String? = nil, prefillLastName: String? = nil) {
        self.prefillName = prefillName
        self.prefillLastName = prefillLastName
        _name = State(initialValue: prefillName ?? "")
        _lastName = State(initialValue: prefillLastName ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField(loc("名字"), text: $name)
                TextField(loc("姓氏（可选）"), text: $lastName)
                if let err = nameError { Text(err).font(.footnote).foregroundColor(.red) }
            }
            Section {
                LoadingButton(title: loc("继续"), isLoading: isLoading, disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2, fullWidth: true) {
                    Task { await saveName() }
                }
            }
        }
        
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(loc("取消")) { navBridge.dismiss() } } }
        
        .onAppear { Telemetry.shared.logEvent("apple_continue_open", parameters: nil) }
        .onChange(of: error) { _, newValue in
            if let msg = newValue, !msg.isEmpty {
                bannerCenter.enqueue(message: msg, style: .error, source: "apple_continue", onClose: { withAnimation(.easeInOut(duration: 0.25)) { error = nil } })
            }
        }
    }

    private var nameError: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count >= 2 ? nil : loc("请填写至少 2 个字符的名字。")
    }

    private func saveName() async {
        do {
            isLoading = true
            Telemetry.shared.logEvent("apple_continue_save_click", parameters: [
                "name_len": name.trimmingCharacters(in: .whitespacesAndNewlines).count,
                "has_last_name": !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ])
            let updated = try await repo.updateProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), lastName: lastName.isEmpty ? nil : lastName.trimmingCharacters(in: .whitespacesAndNewlines))
            auth.currentUser = updated
            Telemetry.shared.logEvent("apple_continue_save_success", parameters: [
                "name_len": updated.name.trimmingCharacters(in: .whitespacesAndNewlines).count,
                "has_last_name": (updated.lastName?.isEmpty == false)
            ])
            navBridge.dismiss()
        } catch {
            self.error = error.localizedDescription
            Telemetry.shared.logEvent("apple_continue_save_failure", parameters: [
                "error": error.localizedDescription
            ])
            Telemetry.shared.record(error: error)
        }
        isLoading = false
    }
}

#Preview("Apple 继续") {
    NavigationStack { AppleContinueView(prefillName: "", prefillLastName: "") }
        .environmentObject(AuthManager())
}
