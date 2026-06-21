@preconcurrency import Photos
import SwiftUI

struct PhotoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let library: PhotoLibraryService

    @State private var selection: PhotoSelection?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3
    )

    var body: some View {
        NavigationStack {
            Group {
                if library.hasReadAccess {
                    galleryContent
                } else {
                    permissionContent
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .task {
            await library.requestReadAccess()
        }
        .sheet(item: $selection) { selection in
            PhotoDetailView(
                assetIdentifier: selection.id,
                library: library
            )
        }
        .alert("Photos Issue", isPresented: errorBinding) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "Something went wrong.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { isPresented in
                if !isPresented { library.errorMessage = nil }
            }
        )
    }

    private var galleryContent: some View {
        ScrollView {
            if library.assets.isEmpty {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Photos you take or save will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(library.assets, id: \.localIdentifier) { asset in
                        Button {
                            selection = PhotoSelection(assetIdentifier: asset.localIdentifier)
                        } label: {
                            PhotoAssetThumbnailView(asset: asset, library: library)
                                .id(asset.localIdentifier)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .refreshable {
            library.refresh()
        }
    }

    private var permissionContent: some View {
        ContentUnavailableView {
            Label("Photos Access Required", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Allow Photos access to view your library here.")
        } actions: {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct PhotoSelection: Identifiable {
    let assetIdentifier: String

    var id: String { assetIdentifier }
}

private struct PhotoAssetThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let asset: PHAsset
    let library: PhotoLibraryService

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var requestedAssetIdentifier: String?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .onAppear {
                loadImage(size: proxy.size)
            }
            .onChange(of: asset.localIdentifier) {
                loadImage(size: proxy.size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Photo")
        .onDisappear {
            cancelRequest()
        }
    }

    private func loadImage(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let identifier = asset.localIdentifier
        if requestedAssetIdentifier == identifier, image != nil {
            return
        }

        cancelRequest()
        requestedAssetIdentifier = identifier
        image = nil
        requestID = library.requestImage(
            for: asset,
            targetSize: CGSize(
                width: max(size.width * displayScale, 240),
                height: max(size.height * displayScale, 240)
            ),
            contentMode: .aspectFill
        ) { image in
            guard requestedAssetIdentifier == identifier else { return }
            self.image = image
        }
    }

    private func cancelRequest() {
        if let requestID {
            library.cancelImageRequest(requestID)
            self.requestID = nil
        }
        requestedAssetIdentifier = nil
    }
}

private struct PhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let assetIdentifier: String
    let library: PhotoLibraryService

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var requestedAssetIdentifier: String?
    @State private var confirmsDeletion = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if library.asset(withIdentifier: assetIdentifier) == nil {
                    ContentUnavailableView("Photo Deleted", systemImage: "trash")
                        .foregroundStyle(.white)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                    .disabled(isDeleting || library.asset(withIdentifier: assetIdentifier) == nil)
                }
            }
        }
        .presentationBackground(.black)
        .task(id: assetIdentifier) {
            loadImage()
        }
        .onDisappear {
            cancelRequest()
        }
        .confirmationDialog(
            "Delete this photo from your library?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                deletePhoto()
            }
        }
    }

    private func loadImage() {
        let identifier = assetIdentifier
        cancelRequest()
        requestedAssetIdentifier = identifier
        image = nil

        guard let asset = library.asset(withIdentifier: identifier) else {
            return
        }

        requestID = library.requestFullImage(for: asset) { image in
            guard requestedAssetIdentifier == identifier else { return }
            self.image = image
        }
    }

    private func cancelRequest() {
        if let requestID {
            library.cancelImageRequest(requestID)
            self.requestID = nil
        }
        requestedAssetIdentifier = nil
    }

    private func deletePhoto() {
        guard let asset = library.asset(withIdentifier: assetIdentifier) else {
            dismiss()
            return
        }

        isDeleting = true
        Task {
            do {
                try await library.delete(asset)
                dismiss()
            } catch {
                library.errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
    }
}
