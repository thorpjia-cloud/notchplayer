import AppKit
import Combine
import ServiceManagement

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var isChanging = false
    @Published private(set) var errorMessage: String?
    private let service = SMAppService.mainApp

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }
    var detail: String {
        if let errorMessage { return errorMessage }
        switch status {
        case .enabled: return "登录 Mac 后在后台启动，播放音乐时自动出现。"
        case .requiresApproval: return "尚未启用，请在系统登录项中允许 notchplayer。"
        case .notFound: return "请将 notchplayer 放入“应用程序”后重新打开。"
        default: return "登录 Mac 后自动启动，无需每次手动打开。"
        }
    }

    func refresh() {
        // Read the OS state instead of persisting a second preference that could become stale.
        let current = service.status
        if current != status { errorMessage = nil }
        status = current
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        errorMessage = nil
        refresh()
        if enabled && needsApproval { openSystemSettings(); return }
        guard enabled != isEnabled else { return }
        isChanging = true
        Task {
            defer { refresh(); isChanging = false }
            do {
                if enabled { try service.register() }
                else { try await service.unregister() }
            } catch {
                refresh()
                if !needsApproval && enabled != isEnabled {
                    errorMessage = "未能更改自启动设置，请重试或在系统登录项中设置。"
                }
                NSLog("notchplayer login item error: %@", String(describing: error))
            }
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
