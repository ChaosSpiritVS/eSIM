import SwiftUI

struct AgentBillRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 12)
                RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 12)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 16)
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}