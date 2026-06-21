import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.parmscript.tippycam"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let photos = Logger(subsystem: subsystem, category: "photos")
}
