import AppKit

@main
@MainActor
enum MacPetMain {
    static func main() {
        if CommandLine.arguments.contains("--verify-release") {
            do { try ReleaseVerification.run() }
            catch { fputs("Release verification failed: \(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

