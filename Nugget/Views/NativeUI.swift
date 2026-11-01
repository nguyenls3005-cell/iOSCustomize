import SwiftUI
import UIKit

// Shared theme + components. Every page in the app draws from these, so a
// change here reaches the whole app. Corner radii follow the iOS 26 softer
// look: 28 pt cards, 20 pt buttons, larger gutters throughout. The palette is
// a single deep-orange accent (EnsWilde family), not the system blue, so
// every filled action is unambiguously this app's.

// MARK: - Palette

enum AppPalette {
    /// Primary accent — deep orange, ~#FF6B0D.
    static let accent     = Color(red: 1.00, green: 0.42, blue: 0.05)
    /// Darker shade, for gradient ends and pressed states.
    static let accentDeep = Color(red: 0.88, green: 0.31, blue: 0.02)
    static let danger     = Color(red: 1.00, green: 0.30, blue: 0.26)
    static let success    = Color(red: 0.20, green: 0.78, blue: 0.36)
    static let warning    = Color(red: 1.00, green: 0.58, blue: 0.00)

    // Radii — iOS 26 (large, continuous)
    static let rCard:   CGFloat = 28
    static let rInner:  CGFloat = 20
    static let rButton: CGFloat = 20
    static let rTile:   CGFloat = 22
    static let rSmall:  CGFloat = 14

    // Spacing
    static let sCard:   CGFloat = 20
    static let sGap:    CGFloat = 14
    static let sScreen: CGFloat = 16
}

// MARK: - Notes

struct NativeNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NativeSafetyNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppPalette.danger)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Legacy buttons
//
// Names and signatures preserved so no existing page breaks. Style replaced
// with the new flat accent fill and the new radii.

struct NativePrimaryButton: View {
    let title: String
    var systemImage: String?
    var running = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if running {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(
                AppPalette.accent.opacity(disabled ? 0.4 : 1),
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
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(
                AppPalette.danger.opacity(disabled ? 0.4 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
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
            withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                Spacer(minLength: 0)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.secondary)
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
                    .fill(.thinMaterial)
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
                Button("Done") { Self.resignFirstResponder() }
            }
        }
    }

    private static func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - Card

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
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
    }
}

// MARK: - Card header

struct AppCardHeader: View {
    let icon: String
    let title: String
    var tint: Color = AppPalette.accent
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title).font(.system(size: 15, weight: .semibold))
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
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(
                (destructive ? AppPalette.danger : AppPalette.accent)
                    .opacity(disabled ? 0.4 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || running)
    }
}

// MARK: - Chip

struct AppChip: View {
    let text: String
    let tone: GoldenTone
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(tone.nativeColor)
        .background(tone.nativeColor.opacity(0.13), in: Capsule())
    }
}

// MARK: - Divider

struct AppDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
    }
}

// MARK: - Empty state

struct AppEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppPalette.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}