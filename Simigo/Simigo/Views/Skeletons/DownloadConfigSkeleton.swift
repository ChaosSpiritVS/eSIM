import SwiftUI

struct DownloadConfigSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .frame(width: 220, height: 36)
            .foregroundStyle(.secondary.opacity(0.25))
            .redacted(reason: .placeholder)
            .shimmer(active: true)
            .accessibilityHidden(true)
    }
}