import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUserDriver {
    enum Phase { case idle, checking, downloading, extracting, ready, installing, current, failed }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var message = "检查是否有可用的新版本"
    @Published private(set) var progress: Double = 0
    @Published private(set) var automaticChecks = true
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var newVersion = ""
    var showSettings: (() -> Void)?
    private var cancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private var observations: [NSKeyValueObservation] = []
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                         userDriver: self, delegate: nil)

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var buttonTitle: String {
        switch phase {
        case .ready: return "重启并更新"
        case .checking: return "正在检查…"
        case .downloading: return "正在下载…"
        case .extracting: return "正在准备…"
        case .installing: return "正在重启…"
        default: return "检查更新"
        }
    }
    var buttonEnabled: Bool { phase == .ready || canCheck }
    var canCancel: Bool { cancellation != nil && (phase == .checking || phase == .downloading) }
    var isBusy: Bool { [.checking, .downloading, .extracting, .installing].contains(phase) }

    func start() {
        observations = [
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.lastCheck = updater.lastUpdateCheckDate }
            }
        ]
        do { try updater.start() }
        catch { fail(error) }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        // Sparkle owns persistence and the schedule so the checkbox cannot drift from the updater.
        updater.automaticallyChecksForUpdates = enabled
    }

    func performPrimaryAction() {
        if phase == .ready, let reply = installReply {
            installReply = nil
            phase = .installing
            message = "正在安装并重新打开 notchplayer…"
            reply(.install)
        } else { checkForUpdates() }
    }

    func checkForUpdates() {
        if updater.canCheckForUpdates { updater.checkForUpdates() }
        else { showSettings?() }
    }

    func cancel() {
        let action = cancellation
        cancellation = nil
        phase = .idle
        message = "已取消，可随时重新检查"
        action?()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .checking
        message = "正在检查 GitHub 上的最新版本…"
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        newVersion = appcastItem.displayVersionString
        guard !appcastItem.isInformationOnlyUpdate else {
            phase = .failed
            message = "此版本暂无可在应用内安装的更新包，请稍后重试。"
            reply(.dismiss)
            return
        }
        // A resumed installation must still wait for an explicit restart, never restart on a scheduled check.
        if state.stage == .installing { showReady(toInstallAndRelaunch: reply) }
        else { reply(.install) }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let latest = (error as NSError).userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        if let latest, SUStandardVersionComparator.default.compareVersion(latest.versionString, toVersion: build) == .orderedDescending {
            phase = .failed
            message = "新版本暂不适用于当前系统。\(error.localizedDescription)"
        } else {
            phase = .current
            message = latest == nil ? "暂无可用更新" : "当前已是最新版本"
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        expectedBytes = 0; receivedBytes = 0; progress = 0
        phase = .downloading
        message = "正在下载 notchplayer \(newVersion)…"
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        progress = expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : 0
    }
    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil; progress = 0
        phase = .extracting
        message = "下载完成，正在校验并准备更新…"
    }
    func showExtractionReceivedProgress(_ progress: Double) { self.progress = progress }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        cancellation = nil
        phase = .ready
        message = "\(newVersion) 已准备好，重启 notchplayer 即可完成更新。"
        showSettings?()
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        message = "正在安装并重新打开 notchplayer…"
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        phase = .current
        message = "更新完成"
        acknowledgement()
    }
    func dismissUpdateInstallation() {
        cancellation = nil; installReply = nil
        if isBusy || phase == .ready {
            phase = .idle
            message = "检查是否有可用的新版本"
        }
    }
    func showUpdateInFocus() { showSettings?() }
    private func fail(_ error: Error) {
        phase = .failed
        let code = (error as NSError).code
        switch code {
        case Int(SUError.appcastError.rawValue), Int(SUError.downloadError.rawValue):
            message = "暂时无法连接更新源，请检查网络后重试。"
        case Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue):
            message = "更新签名校验未通过，已停止安装。请稍后重试。"
        case Int(SUError.runningFromDiskImageError.rawValue), Int(SUError.runningTranslocated.rawValue):
            message = "请先将 notchplayer 放入“应用程序”，再检查更新。"
        default:
            message = "更新未完成，请稍后重试。"
        }
        NSLog("notchplayer update error: %@", String(describing: error))
    }
}
