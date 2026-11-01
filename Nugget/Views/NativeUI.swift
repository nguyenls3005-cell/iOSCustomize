import SwiftUI
import UIKit

// Theme chung. Backdrop mesh gradient tĩnh, card .regularMaterial +
// compositingGroup(), nút Liquid Glass native.

enum AppPalette {
    static let accent     = Color(red: 1.00, green: 0.48, blue: 0.00)
    static let accentDeep = Color(red: 0.92, green: 0.38, blue: 0.00)
    static let danger     = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let success    = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let warning    = Color(red: 1.00, green: 0.80, blue: 0.00)

    static let rCard:   CGFloat = 24
    static let rInner:  CGFloat = 16
    static let rSmall:  CGFloat = 10

    static let sCard:   CGFloat = 16
    static let sGap:    CGFloat = 12
    static let sScreen: CGFloat = 16
}

// MARK: - Backdrop

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
            [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
        ], colors: colors)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var colors: [Color] {
        let base = Color(uiColor: .systemGroupedBackground)
        if scheme == .dark {
            return [
                base, base, base,
                base, AppPalette.accent.opacity(0.08), base,
                base, Color(red: 0.35, green: 0.20, blue: 0.55).opacity(0.06), base
            ]
        } else {
            return [
                base, base, base,
                base, AppPalette.accent.opacity(0.10), base,
                base, Color(red: 0.55, green: 0.30, blue: 0.95).opacity(0.05), base
            ]
        }
    }
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

// MARK: - Legacy buttons (Liquid Glass)

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
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(AppPalette.accent)
        .controlSize(.large)
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
        }
        .buttonStyle(.glassProminent)
        .tint(AppPalette.danger)
        .controlSize(.large)
        .disabled(disabled)
    }
}

// MARK: - Collapsible header

struct NativeCollapsibleHeader: View {
    let title: String
    @Binding var collapsed: Bool

    var body: some View {
        Button {
            collapsed.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(AppPalette.accent)
                Spacer(minLength: 0)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppPalette.accent.opacity(0.7))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.none, value: collapsed)
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
                    .fill(.regularMaterial)
                    .overlay(
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(AppPalette.accent)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.75)
        )
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

struct AppCard<Content: View>: View {
    var padding: CGFloat = AppPalette.sCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.75)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.15))
                )
            Text(title).font(.subheadline.weight(.bold))
            Spacer(minLength: 6)
            if let trailing { trailing }
        }
    }
}

// MARK: - Button
//
// .glassProminent và .glass là PrimitiveButtonStyle, không phải ButtonStyle.
// Ternary không resolve được (`some ButtonStyle` không nhận PrimitiveButtonStyle
// trực tiếp) → phải tách if/else trong Group để mỗi nhánh có style riêng.

struct AppButton: View {
    let title: String
    var systemImage: String? = nil
    var running: Bool = false
    var disabled: Bool = false
    var destructive: Bool = false
    var prominent: Bool = true
    let action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action, label: labelContent)
                    .buttonStyle(.glassProminent)
                    .tint(destructive ? AppPalette.danger : AppPalette.accent)
            } else {
                Button(action: action, label: labelContent)
                    .buttonStyle(.glass)
                    .tint(destructive ? AppPalette.danger : AppPalette.accent)
            }
        }
        .controlSize(.large)
        .disabled(disabled || running)
    }

    @ViewBuilder
    private func labelContent() -> some View {
        HStack(spacing: 8) {
            if running {
                ProgressView().controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(title).font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chip

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
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .foregroundStyle(tone.nativeColor)
        .background(
            Capsule(style: .continuous).fill(tone.nativeColor.opacity(0.15))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tone.nativeColor.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let icon: String
    let label: String
    let value: String
    let tone: GoldenTone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone.nativeColor)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .compositingGroup()
    }
}

// MARK: - Divider

struct AppDivider: View {
    var body: some View { Divider() }
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