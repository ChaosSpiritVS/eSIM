import SwiftUI

struct LoadingButton: View {
    let title: String
    let isLoading: Bool
    var disabled: Bool = false
    var fullWidth: Bool = true
    var leadingIcon: String? = nil
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().progressViewStyle(.circular)
                } else if let icon = leadingIcon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .center)
        }
        .disabled(disabled || isLoading)
        .tint(tint)
    }
}