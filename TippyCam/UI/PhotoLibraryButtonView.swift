import SwiftUI

struct PhotoLibraryButtonView: View {
    let image: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 54, height: 54)
            .background(.black.opacity(0.34))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Photos")
    }
}
