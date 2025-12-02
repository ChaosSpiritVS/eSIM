import SwiftUI

struct QRCodeSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .frame(width: 180, height: 180)
            .foregroundStyle(.secondary.opacity(0.25))
            .redacted(reason: .placeholder)
            .shimmer(active: true)
            .accessibilityHidden(true)
    }
}