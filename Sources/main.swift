import Cocoa

private func appendLog(_ line: String, to path: String) {
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

private func logLine(_ text: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(text)\n"
    let supportDirectory = NSHomeDirectory() + "/Library/Application Support/ZoneFlip"
    try? FileManager.default.createDirectory(atPath: supportDirectory, withIntermediateDirectories: true)
    appendLog(line, to: supportDirectory + "/cli.log")
    appendLog(line, to: "/tmp/zoneflip-cli.log")
    print(line, terminator: "")
}


let arguments = CommandLine.arguments

// Renders the menu without a GUI session; used to sanity-check menu wiring.
if arguments.contains("--dump-menu") {
    let delegate = AppDelegate()
    let menu = NSMenu()
    delegate.menuNeedsUpdate(menu)
    for item in menu.items {
        if item.isSeparatorItem {
            print("---")
            continue
        }
        print("\(item.isEnabled ? "*" : " ") \(item.title)")
        if let submenu = item.submenu {
            for child in submenu.items {
                print("    \(child.state == .on ? "[x]" : "[ ]") \(child.title)")
            }
        }
    }
    exit(0)
}
if arguments.count > 1 { logLine("launch args=\(arguments.dropFirst().joined(separator: " "))") }
let controller = ZoneController()

// Headless helpers, used for diagnostics and for automated checks.
if arguments.contains("--diagnose") {
    let text = """
    zone=\(controller.currentZoneID)
    pretty=\(controller.prettyName)
    helper_on_disk=\(controller.helperInstalledOnDisk)
    helper_ready=\(controller.helperReady)
    auto_follow=\(controller.autoFollow)
    login_item=\(controller.loginItemEnabled)
    title=\(controller.menuBarTitle())
    exit=\(controller.lastExitSummary ?? "none")
    """
    logLine("diagnose\n" + text)
    exit(0)
}

if let index = arguments.firstIndex(of: "--set"), index + 1 < arguments.count {
    let raw = arguments[index + 1]
    let all = [ZoneController.cn] + ZoneController.usOptions
    if let option = all.first(where: { $0.helperArg == raw || $0.id == raw }) {
        controller.apply(option) { ok, message in
            logLine("set \(raw) -> \(option.id): ok=\(ok) \(message)")
            exit(ok ? 0 : 1)
        }
        RunLoop.main.run()
    } else {
        logLine("set \(raw): unknown zone (use cn, us-west, us-east, us-central, us-mountain)")
        exit(2)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
