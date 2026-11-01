import SwiftUI
import UIKit

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
            .font(.footnote)
            .foregroundStyle(.red)
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
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: disabled ? [.gray, .gray] : [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: disabled ? .clear : .blue.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(running || disabled)
        .buttonStyle(.plain)
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
            .frame(height: 50)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}

// Logo xài Vector thuần, đéo bao giờ lỗi ảnh
struct NativeLogo: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: .cyan.opacity(0.4), radius: 12, y: 6)
            
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

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

enum GoldenTone {
    case primary, secondary, disabled, accent, success, error, warning
}

extension GoldenTone {
    var nativeColor: Color {
        switch self {
        case .primary: return .primary
        case .secondary: return .secondary
        case .disabled: return Color(.tertiaryLabel)
        case .accent: return .blue
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }
}