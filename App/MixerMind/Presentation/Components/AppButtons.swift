import SwiftUI

// MARK: - Circle Icon Button (44x44)

struct CircleIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .circle)
    }
}

// MARK: - Circle Icon Menu (44x44, for Menu wrappers)

struct CircleIconMenuLabel: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .glassEffect(in: .circle)
    }
}

// MARK: - Pill Button (height: 48)

struct PillButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var maxWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.primary)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(height: 48)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, 16)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
        .disabled(isLoading)
    }
}
