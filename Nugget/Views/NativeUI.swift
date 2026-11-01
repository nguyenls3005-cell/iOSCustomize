import SwiftUI
import UIKit

// Flat theme. Cam tươi #FF7A00, đỏ #FF3B30, xanh #34C759. Card không shadow.

enum AppPalette {
    // Cam tươi — #FF7A00, rõ, không gỉ sét
    static let accent     = Color(red: 1.00, green: 0.48, blue: 0.00)
    static let accentDeep = Color(red: 0.92, green: 0.38, blue: 0.00)
    // Đỏ iOS — #FF3B30
    static let danger     = Color(red: 1.00, green: 0.23, blue: 0.19)
    // Xanh iOS — #34C759
    static let success    = Color(red: 0.20, green: 0.78, blue: 0.35)
    // Vàng iOS — #FFCC00
    static let warning    = Color(red: 1.00, green: 0.80, blue: 0.00)

    static let rCard:   CGFloat = 22
    static let rInner:  CGFloat = 14
    static let rButton: CGFloat = 14
    static let rSmall:  CGFloat = 10

    static let sCard:   CGFloat = 14
    static let sGap:    CGFloat = 10
    static let sScreen: CGFloat = 14
}

struct NativeNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NativeSafetyNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppPalette.danger)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NativePrimaryButton: View {
    let title: String
    var systemImage: String?
    var running = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if running {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [AppPalette.accent, AppPalette.accentDeep],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(disabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(running || disabled)
    }
}

struct NativeDangerButton: View {
    let title: String
    var systemImage: String?
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [AppPalette.danger, AppPalette.danger.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(disabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct NativeCollapsibleHeader: View {
    let title: String
    @Binding var collapsed: Bool

    var body: some View {
        Button {
            collapsed.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.accent.opacity(0.85))
                Spacer(minLength: 0)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppPalette.accent.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.none, value: collapsed)
    }
}

struct NativeLogo: View {
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let image = NativeLogo.bundledIcon {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay(
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(AppPalette.accent)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    private static let bundledIcon: UIImage? = {
        if let path = Bundle.main.path(forResource: "Logo@2x", ofType: "png"),
           let image = UIImage(contentsOfFile: path) { return image }
        if let path = Bundle.main.path(forResource: "Logo@1x", ofType: "png"),
           let image = UIImage(contentsOfFile: path) { return image }
        return nil
    }()
}

enum GoldenTone {
    case primary, secondary, disabled, accent, success, error, warning
}

extension GoldenTone {
    var nativeColor: Color {
        switch self {
        case .primary:   return .primary
        case .secondary: return .secondary
        case .disabled:  return Color(.tertiaryLabel)
        case .accent:    return AppPalette.accent
        case .success:   return AppPalette.success
        case .error:     return AppPalette.danger
        case .warning:   return AppPalette.warning
        }
    }
}

extension View {
    func nativeKeyboardDone() -> some View { modifier(NativeKeyboardDone()) }
}

struct NativeKeyboardDone: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { Self.resignFirstResponder() }
                    .foregroundStyle(AppPalette.accent)
                    .fontWeight(.semibold)
            }
        }
    }

    private static func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// Card: solid fill + border accent 0.06. Bắt mắt hơn nhờ viền màu accent
// nhưng vẫn KHÔNG shadow — không gây lag.
struct AppCard<Content: View>: View {
    var padding: CGFloat = AppPalette.sCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                    .strokeBorder(AppPalette.accent.opacity(0.08), lineWidth: 0.75)
            )
    }
}

struct AppCardHeader: View {
    let icon: String
    let title: String
    var tint: Color = AppPalette.accent
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).font(.subheadline.weight(.bold))
            Spacer(minLength: 6)
            if let trailing { trailing }
        }
    }
}

struct AppButton: View {
    let title: String
    var systemImage: String? = nil
    var running: Bool = false
    var disabled: Bool = false
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if running {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.callout.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled || running)
    }

    private var buttonBackground: some ShapeStyle {
        let base = destructive ? AppPalette.danger : AppPalette.accent
        let deep = destructive ? AppPalette.danger.opacity(0.85) : AppPalette.accentDeep
        return LinearGradient(colors: [base, deep], startPoint: .top, endPoint: .bottom)
            .opacity(disabled ? 0.35 : 1)
    }
}

struct AppChip: View {
    let text: String
    let tone: GoldenTone
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tone.nativeColor)
        .background(tone.nativeColor.opacity(0.14), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tone.nativeColor.opacity(0.22), lineWidth: 0.5)
        )
    }
}

struct AppDivider: View {
    var body: some View { Divider() }
}

struct AppEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppPalette.accent.opacity(0.8))
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}