import SwiftUI

struct CaptureControlsView: View {
    let isProcessing: Bool
    let capture: () -> Void

    var body: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.28))
                    .frame(width: 90, height: 90)
                Circle()
                    .stroke(.white.opacity(0.92), lineWidth: 5)
                    .frame(width: 82, height: 82)
                Circle()
                    .fill(.white)
                    .frame(width: 68, height: 68)
                if isProcessing {
                    ProgressView()
                        .tint(.black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(isProcessing ? "Processing photo" : "Take photo")
    }
}
