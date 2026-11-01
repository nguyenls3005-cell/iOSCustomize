import SwiftUI
import UIKit

// Shared building blocks for the native screens.
//
// The page-level components are deliberately plain: a solid card, a flat
// button, a small chip. No gradients, no materials beyond what a card needs to
// sit on the grouped background, no animation. The look differs from the old
// `List(.insetGrouped)` layout because it is a stack of cards, not because it
// is decorated.

// MARK: - Palette
//
// The one accent the app paints with. A deep orange — the same family as
// EnsWilde's — instead of the system blue, so a filled action is unambiguous
// in a screenshot. Two depths: the fill, and a slightly darker one for the
// bottom of any gradient that needs one.

enum AppPalette {
    /// The primary accent. Deep orange, ~#FF6B0D.
    static let accent     = Color(red: 1.00, green: 0.42, blue: 0.05)
    /// A darker shade for gradient ends and pressed states.
    static let accentDeep = Color(red: 0.88, green: 0.31, blue: 0.02)
}

// MARK: - Notes

/// A muted explanatory line: secondary, footnote, wraps rather than truncates.
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

/// A line that says what an action costs, in the system danger tone.
struct NativeSafetyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Legacy primary/danger buttons
//
// Kept for every page that already uses them (FirstRunView, ResetPagesSheet,
// PresetManagerView, ...). The HomeView has moved to `AppButton` below, but
// nothing here is removed so no other screen breaks.

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
                }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(AppPalette.accent)
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
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
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
                Spacer(minLength: 0)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(AppPalette.accent)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
        case .primary: return .primary
        case .secondary: return .secondary
        case .disabled: return Color(.tertiaryLabel)
        case .accent: return AppPalette.accent
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
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

// MARK: - Card surface
//
// The one container the redesigned HomeView puts every section in. A rounded
// rectangle on `secondarySystemGroupedBackground`, a thin border, and no
// shadow — a card, not a floating tile.

struct AppCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

/// The card header: a small icon and a section title, in one line. Used on
/// every card so the page reads as a set of sections, not as a wall of rows.
struct AppCardHeader: View {
    let icon: String
    let title: String
    var tint: Color = AppPalette.accent
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Button
//
// A flat filled button: rounded rectangle, white text on the accent (or red)
// fill. This is the HomeView's action primitive. It has no ring, no gradient,
// no shadow — just a colour change and a corner radius.
//
// Argument order is fixed: title, systemImage, running, disabled, destructive,
// action. `disabled` must precede `destructive`; calling `AppButton(title:,
// systemImage:, destructive:, disabled:)` will not compile.

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
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                (destructive ? Color.red : AppPalette.accent)
                    .opacity(disabled ? 0.4 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || running)
    }
}

// MARK: - Chip
//
// A small status label: an optional glyph and a short phrase on a tinted
// capsule. Replaces a whole List row that used to hold one sentence.

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
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tone.nativeColor)
        .background(tone.nativeColor.opacity(0.13), in: Capsule())
    }
}