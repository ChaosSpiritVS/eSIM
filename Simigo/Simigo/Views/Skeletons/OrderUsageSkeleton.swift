import SwiftUI

struct OrderUsageSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 4).frame(width: 220, height: 10)
                }
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 12)
                    RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 10)
                }
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 12)
                    RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 10)
                }
            }
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}