import SwiftUI

struct KeyboardShortcutItem: Identifiable, Equatable {
    let title: String
    let keys: [String]
    var id: String { title }
}

struct KeyboardShortcutSection: Identifiable, Equatable {
    let title: String
    let items: [KeyboardShortcutItem]
    var id: String { title }
}

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var closeHovered = false

    static var sections: [KeyboardShortcutSection] { [
        KeyboardShortcutSection(title: L10n.t("导航"), items: [
            KeyboardShortcutItem(title: L10n.t("显示快捷键"), keys: ["/", "?"]),
            KeyboardShortcutItem(title: L10n.t("打开或关闭左侧栏"), keys: ["⌘ B", "["]),
            KeyboardShortcutItem(title: L10n.t("搜索"), keys: ["⌘ K", "⌘ F"]),
            KeyboardShortcutItem(title: L10n.t("回到首页"), keys: ["H"]),
            KeyboardShortcutItem(title: L10n.t("后退"), keys: ["←"]),
            KeyboardShortcutItem(title: L10n.t("前进"), keys: ["→"]),
            KeyboardShortcutItem(title: L10n.t("刷新"), keys: ["R"]),
            KeyboardShortcutItem(title: L10n.t("打开或关闭频道更新"), keys: ["U"]),
            KeyboardShortcutItem(title: L10n.t("设置"), keys: ["⌘ ,"])
        ]),
        KeyboardShortcutSection(title: L10n.t("收藏夹"), items: [
            KeyboardShortcutItem(title: L10n.t("首页"), keys: ["⌘ 1"]),
            KeyboardShortcutItem(title: L10n.t("第 1–7 个收藏夹"), keys: ["⌘ 2 – ⌘ 8"]),
            KeyboardShortcutItem(title: L10n.t("最后一个收藏夹"), keys: ["⌘ 9"]),
            KeyboardShortcutItem(title: L10n.t("新建收藏夹"), keys: ["⌘ N"])
        ]),
        KeyboardShortcutSection(title: L10n.t("视频播放"), items: [
            KeyboardShortcutItem(title: L10n.t("播放或暂停"), keys: [L10n.t("空格")]),
            KeyboardShortcutItem(title: L10n.t("保存到收藏夹"), keys: ["B", "S"]),
            KeyboardShortcutItem(title: L10n.t("影院模式 / 播放器全屏"), keys: ["F"]),
            KeyboardShortcutItem(title: L10n.t("缓存视频"), keys: ["D"]),
            KeyboardShortcutItem(title: L10n.t("静音"), keys: ["M"]),
            KeyboardShortcutItem(title: L10n.t("字幕"), keys: ["C"])
        ])
    ] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("键盘快捷键"))
                        .font(.system(size: 22, weight: .semibold))
                    Text(L10n.t("单键快捷键在输入文字时不会触发。"))
                        .font(.system(size: 12))
                        .foregroundStyle(KumoTheme.subtle)
                }
                Spacer()
                Button { dismiss() } label: {
                    KumoIcon("x", size: 16)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(closeHovered ? KumoTheme.text.opacity(0.72) : KumoTheme.subtle)
                        .background(closeHovered ? KumoTheme.tint : KumoTheme.sidebar, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .help(L10n.t("关闭"))
                .accessibilityLabel(L10n.t("关闭"))
                .keyboardShortcut(.cancelAction)
                .animation(.easeOut(duration: 0.12), value: closeHovered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Self.sections) { section in
                        shortcutSection(section)
                    }
                }
                .padding(.trailing, 6)
            }
        }
        .padding(24)
        .frame(width: 520, height: 590)
        .background(KumoTheme.canvas)
        .foregroundStyle(KumoTheme.text)
        .buttonStyle(KumoButtonStyle())
        .tint(KumoTheme.brand)
    }

    private func shortcutSection(_ section: KeyboardShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KumoTheme.subtle)
            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    HStack(spacing: 16) {
                        Text(item.title)
                            .font(.system(size: 13))
                        Spacer(minLength: 12)
                        HStack(spacing: 6) {
                            ForEach(Array(item.keys.enumerated()), id: \.offset) { index, key in
                                if index > 0 {
                                    Text(L10n.t("或"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(KumoTheme.subtle)
                                }
                                Text(key)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .frame(minWidth: 30, minHeight: 26)
                                    .background(KumoTheme.tint,
                                                in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(minHeight: 40)
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 6)
            .background(KumoTheme.sidebar, in: RoundedRectangle(cornerRadius: KumoTheme.radius))
        }
    }
}

enum KeyboardShortcutsShortcut {
    static func matches(_ event: NSEvent, firstResponder: NSResponder?) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isShortcut = (modifiers.isEmpty && (event.characters == "/" || event.characters == "?")) ||
            (modifiers == .shift &&
             (event.characters == "?" || event.charactersIgnoringModifiers == "/"))
        guard event.type == .keyDown,
              !event.isARepeat,
              isShortcut,
              !(firstResponder is NSTextView || firstResponder is NSTextField) else { return false }
        return true
    }
}

struct KeyboardShortcutsShortcutMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.window = window
        }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.action = action
        context.coordinator.window = nsView.window
    }

    static func dismantleNSView(_ nsView: WindowTrackingView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        weak var window: NSWindow?
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.window,
                      window.isKeyWindow,
                      window.attachedSheet == nil,
                      event.window == nil || event.window === window,
                      KeyboardShortcutsShortcut.matches(event, firstResponder: window.firstResponder) else {
                    return event
                }
                self.action()
                return nil
            }
        }

        func invalidate() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    final class WindowTrackingView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}
