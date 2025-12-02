import SwiftUI

struct CountryRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).frame(width: 34, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 12)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary).opacity(0.25)
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}