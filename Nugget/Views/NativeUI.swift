import SwiftUI
import UIKit

// Theme chung. Đã tối ưu cho cuộn mượt:
// - Card dùng solid color + 1 shadow nhỏ (bỏ material blur + double shadow)
// - Chip dùng solid tint (bỏ material)
// - Button 1 shadow nhỏ (bỏ double shadow)
// - Gradient vẫn giữ ở button để không phẳng, nhưng rất nhẹ.

enum AppPalette {
    static let accent     = Color(red: 0.87, green: 0.44, blue: 0.20)
    static let accentDeep = Color(red: 0.72, green: 0.34, blue: 0.13)
    static let danger     = Color(red: 0.88, green: 0.31, blue: 0.28)
    static let success    = Color(red: 0.22, green: 0.68, blue: 0.38)
    static let warning    = Color(red: 0.90, green: 0.58, blue: 0.12)

    static let rCard:   CGFloat = 24
    static let rInner:  CGFloat = 16
    static let rButton: CGFloat = 16
    static let rSmall:  CGFloat = 12

    static let sCard:   CGFloat = 16
    static let sGap:    CGFloat = 10
    static let sScreen: CGFloat = 16
}

// MARK: - Notes

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

// MARK: - Legacy buttons

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
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [AppPalette.accent, AppPalette.accentDeep],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(disabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
            .shadow(color: AppPalette.accentDeep.opacity(disabled ? 0 : 0.18),
                    radius: 4, y: 2)
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
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [AppPalette.danger, AppPalette.danger.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(disabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
            .shadow(color: AppPalette.danger.opacity(disabled ? 0 : 0.15),
                    radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Collapsible header

struct NativeCollapsibleHeader: View {
    let title: String
    @Binding var collapsed: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logo

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

// MARK: - Tone

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

// MARK: - Keyboard

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

// MARK: - Card
//
// Đã bỏ material blur (nguyên nhân chính gây lag cuộn).
// Solid fill + 1 shadow nhỏ + overlay gradient 3% (rẻ hơn material nhiều).

struct AppCard<Content: View>: View {
    var padding: CGFloat = AppPalette.sCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.03), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 6)
            if let trailing { trailing }
        }
    }
}

// MARK: - Button

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
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous))
            .shadow(color: shadowTint.opacity(disabled ? 0 : 0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled || running)
    }

    private var shadowTint: Color { destructive ? AppPalette.danger : AppPalette.accentDeep }

    private var buttonBackground: some ShapeStyle {
        let base = destructive ? AppPalette.danger : AppPalette.accent
        let deep = destructive ? AppPalette.danger.opacity(0.85) : AppPalette.accentDeep
        return LinearGradient(colors: [base, deep], startPoint: .top, endPoint: .bottom)
            .opacity(disabled ? 0.35 : 1)
    }
}

// MARK: - Chip
//
// Bỏ material, dùng solid tint. Rẻ hơn nhiều.

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
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tone.nativeColor)
        .background(tone.nativeColor.opacity(0.12), in: Capsule(style: .continuous))
    }
}

// MARK: - Divider
//
// Dùng Divider() hệ thống — được tối ưu ở tầng render.

struct AppDivider: View {
    var body: some View {
        Divider()
    }
}

// MARK: - Empty state

struct AppEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppPalette.accent.opacity(0.7))
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
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