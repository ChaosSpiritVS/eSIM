import SwiftUI

struct OrderActionSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).frame(width: 24, height: 24)
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 14)
                Spacer()
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).frame(width: 24, height: 24)
                RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 14)
                Spacer()
            }
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}