import SwiftUI

struct CameraModePicker: View {
    @Binding var selection: CameraMode
    let supportsPortrait: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(foregroundStyle(for: mode))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(.white.opacity(0.18))
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.18), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .accessibilityHint(accessibilityHint(for: mode))
            }
        }
        .padding(3)
        .frame(width: 216, height: 54)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.18), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera mode")
    }

    private func foregroundStyle(for mode: CameraMode) -> Color {
        if mode == .portrait, !supportsPortrait {
            return .white.opacity(0.35)
        }
        return selection == mode ? .yellow : .white.opacity(0.66)
    }

    private func accessibilityHint(for mode: CameraMode) -> String {
        if mode == .portrait, !supportsPortrait {
            return "Portrait is not available on this iPhone."
        }
        return "Switch to \(mode.rawValue) mode."
    }
}
