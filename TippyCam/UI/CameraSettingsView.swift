import SwiftUI

struct CameraSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text("Native capture + Tippy render")
                    } label: {
                        Text("Photo")
                    }
                    LabeledContent {
                        Text("Maximum")
                    } label: {
                        Text("Quality")
                    }
                    LabeledContent {
                        Text("Depth when available")
                    } label: {
                        Text("Portrait")
                    }
                } header: {
                    Text("Capture")
                } footer: {
                    Text(
                        "TippyCam captures with the iPhone camera pipeline, then applies one "
                            + "bright, vivid on-device render before saving."
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
