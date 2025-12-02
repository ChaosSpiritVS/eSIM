import SwiftUI

struct OrderAfterSalesSkeleton: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6).frame(width: 16, height: 16)
            RoundedRectangle(cornerRadius: 8).frame(width: 140, height: 30)
            Spacer()
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}