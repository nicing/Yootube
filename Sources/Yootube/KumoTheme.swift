import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: L10n.t("跟随系统"); case .light: L10n.t("亮色"); case .dark: L10n.t("暗色") }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var icon: String {
        switch self { case .system: "desktop"; case .light: "sun"; case .dark: "moon" }
    }
}

// Apple-inspired neutral tokens shared by AppKit and SwiftUI. Keep all neutral
// surfaces and text on this palette so native and web content stay consistent.
enum KumoTheme {
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
    static func adaptive(_ name: String, light: UInt32, dark: UInt32,
                         lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: name) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return color(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
    static let sidebar = adaptive("KumoSidebar", light: 0xF5F5F5, dark: 0x1E1E1E)
    static let canvas = adaptive("KumoCanvas", light: 0xFFFFFF, dark: 0x2A2A2C)
    static let base = adaptive("KumoBase", light: 0xFAFAFC, dark: 0x2A2A2C)
    static let recessed = adaptive("KumoRecessed", light: 0xF5F5F7, dark: 0x272729)
    static let tint = adaptive("KumoTint", light: 0xD2D2D7, dark: 0x333333,
                               lightAlpha: 0.64)
    static let line = adaptive("KumoLine", light: 0xE0E0E0, dark: 0x333333)
    static let text = adaptive("KumoText", light: 0x1D1D1F, dark: 0xFFFFFF)
    static let subtle = adaptive("KumoSubtle", light: 0x7A7A7A, dark: 0xCCCCCC)
    static let focus = adaptive("KumoFocus", light: 0x1D1D1F, dark: 0xFFFFFF)
    static let placeholder = adaptive("KumoPlaceholder", light: 0xF5F5F7, dark: 0x272729)
    static let skeleton = adaptive("KumoSkeleton", light: 0xF0F0F0, dark: 0x272729)
    static let skeletonHighlight = adaptive("KumoSkeletonHighlight", light: 0xFAFAFC, dark: 0x2A2A2C)
    static let selectedShortcut = adaptive("KumoSelectedShortcut", light: 0xD2D2D7, dark: 0x252527)
    static let ink = Color(nsColor: color(0x1D1D1F))
    static let bodyOnDark = Color(nsColor: color(0xFFFFFF))
    static let surfaceBlack = Color(nsColor: color(0x000000))
    static let brand = Color(red: 0.90, green: 0.04, blue: 0.12)
    static let radiusSmall: CGFloat = 8
    static let radius: CGFloat = 10
    static let radiusPanel: CGFloat = 14
    static func windowColor(dark: Bool) -> NSColor { color(dark ? 0x1E1E1E : 0xF5F5F5) }
}

struct KumoButtonStyle: ButtonStyle {
    enum Variant { case secondary, primary, ghost, row }
    var variant: Variant = .secondary
    var horizontalPadding: CGFloat? = nil
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, variant: variant, enabled: enabled,
                   horizontalPadding: horizontalPadding ?? (variant == .row ? 8 : 12))
    }
    private struct ButtonBody: View {
        let configuration: Configuration
        let variant: Variant
        let enabled: Bool
        let horizontalPadding: CGFloat
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: 36)
                .foregroundStyle(variant == .primary ? KumoTheme.bodyOnDark : KumoTheme.text)
                .background(background, in: RoundedRectangle(cornerRadius: KumoTheme.radius))
                .overlay(RoundedRectangle(cornerRadius: KumoTheme.radius)
                    .strokeBorder(variant == .secondary ? KumoTheme.line : .clear, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: KumoTheme.radius))
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
        private var background: Color {
            if variant == .primary { return KumoTheme.brand.opacity(configuration.isPressed ? 0.8 : 1) }
            if enabled && (hovered || configuration.isPressed) { return KumoTheme.tint }
            return variant == .secondary ? KumoTheme.base : .clear
        }
    }
}

struct KumoInputStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).foregroundStyle(KumoTheme.text)
            .padding(.horizontal, 12).frame(height: 38)
            .background(KumoTheme.base, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(KumoTheme.line))
    }
}

struct KumoIcon: View {
    let name: String
    var size: CGFloat = 16
    init(_ name: String, size: CGFloat = 16) { self.name = name; self.size = size }
    var body: some View {
        Image(nsImage: Self.images[name] ?? Self.images["folder-simple"]!)
            .resizable().renderingMode(.template).scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
    private static let images: [String: NSImage] = {
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("Yootube_Yootube.bundle")
        let bundle = packaged.flatMap(Bundle.init(url:)) ?? Bundle.module
        let urls = bundle.urls(forResourcesWithExtension: "svg", subdirectory: "Icons") ?? []
        return Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            guard let image = NSImage(contentsOf: url) else { return nil }
            // AppKit menus consume the NSImage's intrinsic size, ignoring the SwiftUI frame.
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            return (url.deletingPathExtension().lastPathComponent, image)
        })
    }()
}

struct KumoLabel: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View {
        HStack(spacing: 8) { KumoIcon(icon); Text(title) }
    }
}

struct AppearanceMenu: View {
    @AppStorage("appAppearance") private var appearance = AppAppearance.system
    var body: some View {
        Menu {
            Picker(L10n.t("外观"), selection: $appearance) {
                ForEach(AppAppearance.allCases) { mode in Text(mode.title).tag(mode) }
            }
        } label: {
            KumoIcon(appearance.icon).frame(width: 20, height: 28)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.horizontal, 8)
        .background(KumoTheme.base, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(KumoTheme.line))
        .help(L10n.t("外观：\(appearance.title)")).accessibilityLabel(L10n.t("切换外观"))
    }
}
