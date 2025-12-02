import SwiftUI

private struct ShimmerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = -1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    let highlight = (colorScheme == .dark ? Color.white : Color.black).opacity(0.12)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, highlight, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(20))
                        .frame(width: w * 0.8)
                        .offset(x: x * w)
                        .animation(reduceMotion ? nil : .linear(duration: 1.2).repeatForever(autoreverses: false), value: x)
                }
            )
            .mask(content)
            .onAppear { x = 1.5 }
    }
}

extension View {
    @ViewBuilder
    func shimmer(active: Bool) -> some View {
        if active { self.modifier(ShimmerModifier()) } else { self }
    }
}