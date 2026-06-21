import SwiftUI

struct PermissionDeniedView: View {
    let title: String
    let message: String
    var showsSettingsButton = true

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.fill")
        } description: {
            Text(message)
        } actions: {
            if showsSettingsButton {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(28)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PermissionDeniedView(
            title: "Camera Access Required",
            message: "Allow camera access in Settings to take photos."
        )
    }
    .preferredColorScheme(.dark)
}
