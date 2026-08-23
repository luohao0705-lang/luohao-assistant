import SwiftUI

enum LuohaoDesign {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let card = Color(uiColor: .systemBackground)
    static let accent = Color.orange
    static let accentTint = Color.orange.opacity(0.10)
    static let hairline = Color.primary.opacity(0.08)
    static let radius: CGFloat = 14
    static let compactRadius: CGFloat = 10
}

struct PageSectionHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct SurfaceCardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(LuohaoDesign.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LuohaoDesign.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func surfaceCard(padding: CGFloat = 16, radius: CGFloat = LuohaoDesign.radius) -> some View {
        modifier(SurfaceCardModifier(padding: padding, radius: radius))
    }
}

struct PrimaryActionLabel: View {
    let title: String
    let systemImage: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
            }
            Text(title).font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 46)
    }
}
