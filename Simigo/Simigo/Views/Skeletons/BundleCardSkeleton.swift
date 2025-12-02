import SwiftUI

struct BundleCardSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).frame(width: 44, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 12)
                HStack(spacing: 6) {
                    Capsule().frame(width: 28, height: 14)
                    Capsule().frame(width: 52, height: 14)
                }
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).frame(width: 64, height: 16)
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}