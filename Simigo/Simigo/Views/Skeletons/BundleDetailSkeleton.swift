import SwiftUI

struct BundleDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).frame(width: 44, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 18)
                    RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 12)
                }
                Spacer()
            }
            RoundedRectangle(cornerRadius: 4).frame(width: 100, height: 16)
            Divider()
            RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 16)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).frame(height: 12)
                }
            }
            RoundedRectangle(cornerRadius: 10).frame(height: 44)
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}