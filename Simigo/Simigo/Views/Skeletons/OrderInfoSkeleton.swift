import SwiftUI

struct OrderInfoSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 14); Spacer(); RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 14) }
            HStack { RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 14); Spacer(); RoundedRectangle(cornerRadius: 4).frame(width: 100, height: 14) }
            HStack { RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 14); Spacer(); RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 14) }
            HStack { RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 14); Spacer(); RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 14) }
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}