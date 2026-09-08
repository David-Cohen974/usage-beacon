import AppKit
import SwiftUI

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

extension ProviderSetupStatus {
    var colors: [Color] {
        switch self {
        case .connected, .ready:
            return [BeaconPalette.cyan, BeaconPalette.teal]
        case .checking, .syncing, .waitingForSignIn:
            return [BeaconPalette.amber, BeaconPalette.cyan]
        case .paused, .setupRequired, .signInRequired:
            return [BeaconPalette.amber, BeaconPalette.coral]
        case .needsAttention:
            return [BeaconPalette.danger, BeaconPalette.coral]
        }
    }
}

enum BeaconPalette {
    static let ink = Color(nsColor: .labelColor)
    static let mutedInk = Color(nsColor: .secondaryLabelColor)
    static let cream = dynamic(light: rgba(0.98, 0.96, 0.92), dark: rgba(0.06, 0.08, 0.13))
    static let mist = dynamic(light: rgba(0.91, 0.96, 0.99), dark: rgba(0.10, 0.14, 0.20))
    static let canvas = dynamic(light: rgba(1.00, 1.00, 1.00), dark: rgba(0.04, 0.06, 0.10))
    static let luminousInk = dynamic(light: rgba(0.04, 0.36, 0.42), dark: rgba(0.40, 0.88, 0.84))
    static let teal = Color(red: 0.13, green: 0.69, blue: 0.63)
    static let cyan = Color(red: 0.25, green: 0.56, blue: 0.95)
    static let coral = Color(red: 0.96, green: 0.44, blue: 0.40)
    static let amber = Color(red: 0.99, green: 0.73, blue: 0.29)
    static let peach = Color(red: 1.00, green: 0.86, blue: 0.76)
    static let rose = Color(red: 0.94, green: 0.52, blue: 0.63)
    static let card = dynamic(light: rgba(1.00, 1.00, 1.00, 0.80), dark: rgba(0.08, 0.11, 0.17, 0.84))
    static let cardStrong = Color(nsColor: .controlBackgroundColor)
    static let surfaceSoft = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: .controlBackgroundColor)
    static let surfaceInteractive = Color(nsColor: .controlBackgroundColor)
    static let outline = Color(nsColor: .separatorColor)
    static let glareStrong = dynamic(light: rgba(1.00, 1.00, 1.00, 0.86), dark: rgba(1.00, 1.00, 1.00, 0.16))
    static let glareSoft = dynamic(light: rgba(1.00, 1.00, 1.00, 0.72), dark: rgba(1.00, 1.00, 1.00, 0.08))
    static let glaze = dynamic(light: rgba(1.00, 1.00, 1.00, 0.18), dark: rgba(1.00, 1.00, 1.00, 0.04))
    static let track = dynamic(light: rgba(0.10, 0.14, 0.24, 0.08), dark: rgba(1.00, 1.00, 1.00, 0.10))
    static let shadow = dynamic(light: rgba(0.16, 0.23, 0.32, 0.14), dark: rgba(0.00, 0.00, 0.00, 0.42))
    static let positive = Color(red: 0.18, green: 0.65, blue: 0.42)
    static let caution = Color(red: 0.90, green: 0.55, blue: 0.20)
    static let danger = Color(red: 0.86, green: 0.24, blue: 0.28)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    switch appearance.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua, .aqua, .accessibilityHighContrastAqua]) {
                    case .darkAqua, .accessibilityHighContrastDarkAqua:
                        return dark
                    default:
                        return light
                    }
                }
            )
        )
    }

    private static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

extension ProviderKind {
    var symbolName: String {
        switch self {
        case .codex:
            return "terminal.fill"
        case .cursorPersonal:
            return "sparkles.rectangle.stack"
        case .cursorAdmin:
            return "person.2.crop.square.stack"
        case .claudePersonal:
            return "brain.filled.head.profile"
        case .anthropicAdmin:
            return "brain.head.profile"
        case .manual:
            return "slider.horizontal.3"
        case .customREST:
            return "network"
        }
    }

    var accentColors: [Color] {
        switch self {
        case .codex:
            return [BeaconPalette.ink, BeaconPalette.teal]
        case .cursorPersonal:
            return [BeaconPalette.teal, BeaconPalette.cyan]
        case .cursorAdmin:
            return [BeaconPalette.coral, BeaconPalette.amber]
        case .claudePersonal:
            return [BeaconPalette.rose, BeaconPalette.peach]
        case .anthropicAdmin:
            return [BeaconPalette.rose, BeaconPalette.amber]
        case .manual:
            return [BeaconPalette.amber, BeaconPalette.coral]
        case .customREST:
            return [BeaconPalette.cyan, BeaconPalette.teal]
        }
    }

    var menuBarSymbolName: String {
        switch self {
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .cursorPersonal, .cursorAdmin:
            return "cursorarrow.rays"
        case .claudePersonal, .anthropicAdmin:
            return "sparkle"
        case .manual:
            return "slider.horizontal.3"
        case .customREST:
            return "network"
        }
    }
}

extension ProviderSnapshotState {
    var accentColors: [Color] {
        if errorMessage != nil {
            return [BeaconPalette.danger, BeaconPalette.coral]
        }

        guard let utilizationRatio else {
            return providerKind.accentColors
        }

        switch utilizationRatio {
        case 0 ..< 0.55:
            return [BeaconPalette.teal, BeaconPalette.cyan]
        case 0.55 ..< 0.85:
            return [BeaconPalette.amber, BeaconPalette.coral]
        default:
            return [BeaconPalette.coral, BeaconPalette.rose]
        }
    }
}

// A stationary wash echoes the widget without animating or affecting layout.
struct BeaconBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if contrast == .increased || reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.08, green: 0.12, blue: 0.20),
                       Color(red: 0.08, green: 0.18, blue: 0.24),
                       Color(red: 0.08, green: 0.24, blue: 0.27)]
                    : [Color(red: 0.96, green: 0.98, blue: 1),
                       Color(red: 0.95, green: 0.98, blue: 0.99),
                       Color(red: 0.88, green: 0.96, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

struct BeaconAccentIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(LinearGradient(colors: [BeaconPalette.cyan, BeaconPalette.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
            .accessibilityHidden(true)
    }
}

struct BeaconMetricTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var colors: [Color] = [BeaconPalette.cyan, BeaconPalette.teal]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(BeaconPalette.mutedInk)

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(BeaconPalette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BeaconPalette.mutedInk)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BeaconPalette.cardStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    colors.first?.opacity(0.35) ?? .clear,
                                    BeaconPalette.glareStrong
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: BeaconPalette.shadow, radius: 16, x: 0, y: 10)
    }
}

struct BeaconPill: View {
    let title: String
    var symbol: String? = nil
    var colors: [Color] = [BeaconPalette.cyan, BeaconPalette.teal]

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct BeaconActionButtonStyle: ButtonStyle {
    let colors: [Color]
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? Color.white : BeaconPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var background: AnyShapeStyle {
        AnyShapeStyle(filled ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
    }

    private var borderColor: Color {
        filled ? BeaconPalette.outline.opacity(0.45) : BeaconPalette.glareStrong
    }
}

struct BeaconGaugeBar: View {
    let value: Double
    let colors: [Color]
    var height: CGFloat = 12


    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(BeaconPalette.track)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * clampedValue)
            }
        }
        .frame(height: height)
    }

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }
}

struct ProviderKindOrb: View {
    let kind: ProviderKind

    var body: some View {
        BeaconAccentIcon(symbol: kind.symbolName)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 32, height: 32)
    }
}

struct ForegroundSettingsButton<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    private let label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Button(action: presentSettings, label: label)
    }

    private func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { window in
                window.isVisible && window.canBecomeKey && !(window is NSPanel)
            })?.makeKeyAndOrderFront(nil)
        }
    }
}

struct BeaconCardModifier: ViewModifier {
    let colors: [Color]
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

extension View {
    func beaconCard(colors: [Color], cornerRadius: CGFloat = 28) -> some View {
        modifier(BeaconCardModifier(colors: colors, cornerRadius: cornerRadius))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension DateFormatter {
    static let beaconMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    static let beaconShortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
