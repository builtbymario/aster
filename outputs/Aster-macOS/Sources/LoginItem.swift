import ServiceManagement

/// Opens Aster when the user logs in, so the island, ⌥Space and routines are there all day.
/// macOS keeps the setting and shows it in System Settings → General → Login Items.
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    /// The user turned Aster off in System Settings; only they can turn it back on there.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    static func set(_ on: Bool) throws {
        if on { if !enabled { try SMAppService.mainApp.register() } } else if enabled { try SMAppService.mainApp.unregister() }
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
