enum CameraMode: String, CaseIterable, Identifiable, Sendable {
    case photo = "Photo"
    case portrait = "Portrait"

    var id: Self { self }
}
