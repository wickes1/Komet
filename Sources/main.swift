import AppKit
import Carbon.HIToolbox

class Komet: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let window: NSPanel
    let search: NSTextField
    let list: NSTableView
    var apps: [(name: String, url: URL, icon: NSImage, running: Bool)] = []
    var filtered: [(name: String, url: URL, icon: NSImage, running: Bool)] = []

    override init() {
        // Borderless floating panel
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()

        // Search field
        search = NSTextField(frame: NSRect(x: 20, y: 360, width: 560, height: 28))
        search.placeholderString = "Search apps..."
        search.focusRingType = .none

        // Results list
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 560, height: 320))
        list = NSTableView()
        list.headerView = nil
        list.rowHeight = 36
        list.intercellSpacing = .zero
        list.backgroundColor = .clear
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col.width = 540
        list.addTableColumn(col)
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        window.contentView?.addSubview(search)
        window.contentView?.addSubview(scroll)

        super.init()
        search.delegate = self
        list.dataSource = self
        list.delegate = self
        list.target = self
        list.doubleAction = #selector(launch)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotkey()
        loadApps()
    }

    func registerHotkey() {
        let opts = NSDictionary(object: kCFBooleanTrue!, forKey: kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString) as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 49 { // space
                DispatchQueue.main.async { self?.toggle() }
            }
        }
    }

    func loadApps() {
        apps = []
        let ws = NSWorkspace.shared
        let running = Set(ws.runningApplications.compactMap { $0.bundleURL })

        let dirs = ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"]
        for dir in dirs {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { continue }
            for url in urls where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let icon = ws.icon(forFile: url.path)
                icon.size = NSSize(width: 24, height: 24)
                apps.append((name, url, icon, running.contains(url)))
            }
        }
        apps.sort { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }
        filtered = apps
    }

    func toggle() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            loadApps()
            filtered = apps
            search.stringValue = ""
            list.reloadData()
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(search)
        }
    }

    func controlTextDidChange(_ n: Notification) {
        let q = search.stringValue.lowercased()
        filtered = q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) }
        list.reloadData()
        if !filtered.isEmpty { list.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)):
            list.selectRowIndexes([min(list.selectedRow + 1, filtered.count - 1)], byExtendingSelection: false)
            list.scrollRowToVisible(list.selectedRow)
            return true
        case #selector(NSResponder.moveUp(_:)):
            list.selectRowIndexes([max(list.selectedRow - 1, 0)], byExtendingSelection: false)
            list.scrollRowToVisible(list.selectedRow)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            launch()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window.orderOut(nil)
            return true
        default:
            return false
        }
    }

    @objc func launch() {
        guard list.selectedRow >= 0 else { return }
        NSWorkspace.shared.open(filtered[list.selectedRow].url)
        window.orderOut(nil)
    }
}

extension Komet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let app = filtered[row]
        let cell = NSTableCellView()
        let img = NSImageView(frame: NSRect(x: 4, y: 6, width: 24, height: 24))
        img.image = app.icon
        let txt = NSTextField(labelWithString: app.name + (app.running ? " ●" : ""))
        txt.frame = NSRect(x: 36, y: 8, width: 500, height: 20)
        txt.font = .systemFont(ofSize: 14)
        cell.addSubview(img)
        cell.addSubview(txt)
        return cell
    }
}

let app = NSApplication.shared
let komet = Komet()
app.delegate = komet
app.run()
