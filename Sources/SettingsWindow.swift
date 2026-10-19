import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let updater: AppUpdater

    init(updater: AppUpdater) { self.updater = updater }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "notchplayer 设置"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(updater: updater))
            window.center()
            self.window = window
        }
        // A temporary Dock presence makes the settings window easy to find without changing background playback.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct SettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("notchplayer").font(.system(size: 22, weight: .semibold))
                    Text("版本 \(updater.currentVersion)").foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 15) {
                    Toggle("自动检查更新", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                        .toggleStyle(.checkbox)
                    Text("每天检查新版本。发现更新后直接下载，完成后提醒重启。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: updater.phase == .ready || updater.phase == .current ? "checkmark.circle.fill" : updater.phase == .failed ? "exclamationmark.circle" : "arrow.down.circle")
                            .foregroundStyle(updater.phase == .failed ? Color.orange : Color.accentColor)
                        Text(updater.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    if updater.phase == .downloading || updater.phase == .extracting {
                        ProgressView(value: updater.progress).progressViewStyle(.linear)
                    } else if updater.phase == .checking || updater.phase == .installing {
                        ProgressView().progressViewStyle(.linear)
                    }
                    HStack {
                        if let date = updater.lastCheck {
                            Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if updater.canCancel { Button("取消", action: updater.cancel) }
                        Button(updater.buttonTitle, action: updater.performPrimaryAction)
                            .disabled(!updater.buttonEnabled)
                            .keyboardShortcut(.defaultAction)
                    }
                }.padding(12)
            } label: {
                Label("软件更新", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            }
            HStack(spacing: 5) {
                Text("更新来源").foregroundStyle(.secondary)
                Text("GitHub · thorpjia-cloud/notchplayer")
                Spacer()
            }.font(.caption)
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(width: 520, alignment: .topLeading)
        .frame(minHeight: 390)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
