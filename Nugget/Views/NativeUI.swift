import SwiftUI
import UIKit

// Theme chung cho toàn app. Sửa ở đây là đổi cả app.
// Nhẹ hơn, ấm hơn, ít "nhựa" hơn: accent cam đất, card dùng material thật,
// đổ bóng hai lớp, typography dùng text style hệ thống.

// MARK: - Bảng màu

enum AppPalette {
    /// Accent chính — cam đất ấm, ~#DE7034. Không chói như #FF6B0D.
    static let accent     = Color(red: 0.87, green: 0.44, blue: 0.20)
    static let accentDeep = Color(red: 0.72, green: 0.34, blue: 0.13)
    static let danger     = Color(red: 0.88, green: 0.31, blue: 0.28)
    static let success    = Color(red: 0.22, green: 0.68, blue: 0.38)
    static let warning    = Color(red: 0.90, green: 0.58, blue: 0.12)

    // Góc — iOS 26 mềm hơn
    static let rCard:   CGFloat = 26
    static let rInner:  CGFloat = 18
    static let rButton: CGFloat = 18
    static let rSmall:  CGFloat = 12

    // Khoảng cách
    static let sCard:   CGFloat = 18
    static let sGap:    CGFloat = 12
    static let sScreen: CGFloat = 16
}

// MARK: - Ghi chú

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

// MARK: - Nút cũ (giữ tên, đổi da)
//
// Tên và chữ ký giữ nguyên để không vỡ trang nào. Chỉ style đổi:
// gradient nhẹ, không "kính" chói, chữ trắng trên nền accent ấm.

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
                LinearGradient(
                    colors: [AppPalette.accent, AppPalette.accentDeep],
                    startPoint: .top,
                    endPoint: .bottom
                ).opacity(disabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: AppPalette.accentDeep.opacity(disabled ? 0 : 0.25),
                    radius: 10, y: 4)
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
                LinearGradient(
                    colors: [AppPalette.danger, AppPalette.danger.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                ).opacity(disabled ? 0.35 : 1),
                in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Header thu gọn

struct NativeCollapsibleHeader: View {
    let title: String
    @Binding var collapsed: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { collapsed.toggle() }
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
                    .fill(.ultraThinMaterial)
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
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
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

// MARK: - Bàn phím

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

// MARK: - Thẻ
//
// Bề mặt material thật, không phải solid color. Đổ bóng hai lớp mềm
// (một lớp xa làm nền, một lớp gần làm cạnh) — đây là thứ làm card
// hết "nhựa".

struct AppCard<Content: View>: View {
    var padding: CGFloat = AppPalette.sCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 6)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Header thẻ

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

// MARK: - Nút phẳng
//
// Gradient rất nhẹ từ accent sang accentDeep — đủ để không phẳng nhưng
// không chói. Không có ring, không "kính".

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
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: shadowTint.opacity(disabled ? 0 : 0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(disabled || running)
    }

    private var shadowTint: Color {
        destructive ? AppPalette.danger : AppPalette.accentDeep
    }

    private var buttonBackground: some ShapeStyle {
        let base = destructive ? AppPalette.danger : AppPalette.accent
        let deep = destructive ? AppPalette.danger.opacity(0.85) : AppPalette.accentDeep
        return LinearGradient(colors: [base, deep], startPoint: .top, endPoint: .bottom)
            .opacity(disabled ? 0.35 : 1)
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
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tone.nativeColor)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .strokeBorder(tone.nativeColor.opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Đường kẻ

struct AppDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
    }
}

// MARK: - Trạng thái trống

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