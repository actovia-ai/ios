import Foundation
import PhilharmonicFeature

/// Where the shell starts. Release builds always start on a closed drawer over a new chat; DEBUG builds take
/// `-DrawerOpen` (the drawer open), `-Workspace chat|health|philharmonic` and, in Philharmonic,
/// `-PhilharmonicSelection dashboard|workforce|<group id>` — for screenshots of the drawer and of a group without a
/// finger on the Simulator.
enum ShellLaunch {
    static var drawerOpen: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-DrawerOpen")
        #else
            false
        #endif
    }

    /// `-OpenSettings`: Settings is up on launch (to see a lock cover a sheet).
    static var settingsOpen: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-OpenSettings")
        #else
            false
        #endif
    }

    static var workspace: AppWorkspace {
        switch value(after: "-Workspace") {
        case "health": .health
        case "philharmonic": .philharmonic
        default: .chat
        }
    }

    static var philharmonicSelection: PhilharmonicSelection {
        switch value(after: "-PhilharmonicSelection") {
        case nil: .none
        case "dashboard": .dashboard
        case "workforce": .workforce
        case let id?: .group(id: id, title: "")
        }
    }

    private static func value(after flag: String) -> String? {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        #else
            nil
        #endif
    }
}
