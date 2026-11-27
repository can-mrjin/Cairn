import AppKit

/// Pure AppKit entry point. Avoids SwiftUI's implicit `Settings { EmptyView() }`
/// scene, which macOS can materialize as a blank "Cairn Settings" window on
/// launch, reopen, or state restoration.
@main
@MainActor
enum CodeIslandApp {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.run()
    }
}
