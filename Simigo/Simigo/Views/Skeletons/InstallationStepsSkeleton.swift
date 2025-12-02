import SwiftUI

struct InstallationStepsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .frame(width: 80, height: 12)
            ForEach(0..<3, id: \.self) { idx in
                HStack(alignment: .center, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 240 - CGFloat(idx * 20), height: 10)
                }
            }
        }
        .foregroundStyle(.secondary.opacity(0.25))
        .redacted(reason: .placeholder)
        .shimmer(active: true)
        .accessibilityHidden(true)
    }
}