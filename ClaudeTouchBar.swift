import AppKit
import Foundation

let statusFilePath = "/tmp/claude-touchbar-status"

let spinnerFrames: [Character] = ["·","✢","✳","✶","✻","✽"]

// Claude Code theme colors (dark mode)
// Normal working: "claude" theme = rgb(215,119,87)
let claudeColor = NSColor(red: 215.0/255, green: 119.0/255, blue: 87.0/255, alpha: 1)
// Stalled target: rgb(171,43,63) — shifts toward this when no tokens for 3+ seconds
let stalledColor = NSColor(red: 171.0/255, green: 43.0/255, blue: 63.0/255, alpha: 1)
// Tool shimmer: "claudeShimmer" = rgb(235,159,127)
let shimmerColor = NSColor(red: 235.0/255, green: 159.0/255, blue: 127.0/255, alpha: 1)
// Idle
let idleTextColor = NSColor(red: 120.0/255, green: 120.0/255, blue: 120.0/255, alpha: 1)
let bgColor = NSColor.black

/// Interpolate between two colors
func lerpColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let t = min(1, max(0, t))
    return NSColor(
        red: a.redComponent + (b.redComponent - a.redComponent) * t,
        green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
        blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
        alpha: 1.0
    )
}

func log(_ msg: String) {
    let logPath = "/tmp/claude-touchbar.log"
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

// MARK: - Custom Touch Bar View

class TouchBarLabel: NSView {
    var text: String = "  Claude Ready  " { didSet { needsDisplay = true } }
    var textColor: NSColor = idleTextColor { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    override func touchesEnded(with event: NSEvent) {
        onTap?()
    }

    func setupTap() {
        allowedTouchTypes = .direct
        let gesture = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(gesture)
    }

    @objc private func handleTap() {
        log("Touch Bar tapped!")
        onTap?()
    }

    override var intrinsicContentSize: NSSize {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium)
        ]
        let size = (text as NSString).size(withAttributes: attr)
        return NSSize(width: size.width + 16, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        bounds.fill()

        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: textColor
        ]
        let size = (text as NSString).size(withAttributes: attr)
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attr)
    }

    func updateContent(_ newText: String, color: NSColor) {
        text = newText
        textColor = color
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Touch Bar Controller

class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemIdentifier = NSTouchBarItem.Identifier("com.claude.touchbar.status")
    static let barIdentifier = NSTouchBar.CustomizationIdentifier("com.claude.touchbar")
    static let stripIdentifier = "com.claude.touchbar.status"

    private var label: TouchBarLabel!
    private var currentWord: String = ""
    private var currentMode: String = "idle"  // idle, thinking, responding, tool-use
    private var spinnerFrameIndex: Int = 0

    // Stalled detection (matches Claude Code's RRL function)
    // If no new data for 3s, start shifting to red. Full red at 5s.
    private var lastContentChangeTime: Date = Date()
    private var stalledIntensity: CGFloat = 0.0

    func install() {
        log("Installing Touch Bar...")

        label = TouchBarLabel()
        label.frame = NSRect(x: 0, y: 0, width: 180, height: 30)
        label.setupTap()
        label.onTap = {
            let script = "tell application \"Terminal\" to activate"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }

        let item = NSCustomTouchBarItem(identifier: Self.itemIdentifier)
        item.view = label

        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(Self.stripIdentifier, true)

        let touchBar = NSTouchBar()
        touchBar.customizationIdentifier = Self.barIdentifier
        touchBar.defaultItemIdentifiers = [Self.itemIdentifier]
        touchBar.delegate = self
        NSTouchBar.presentSystemModalTouchBar(touchBar, systemTrayItemIdentifier: Self.stripIdentifier)

        try? "idle".write(toFile: statusFilePath, atomically: true, encoding: .utf8)

        // Poll status file
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkStatusFile()
        }
        // Animation tick
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.spinnerTick()
        }
        // Stalled color update (smooth, 50ms like Claude Code)
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateStalledColor()
        }

        log("Touch Bar installed.")
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == Self.itemIdentifier {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = label
            return item
        }
        return nil
    }

    private var lastFileModTime: Date?

    private func checkStatusFile() {
        // Check file modification time to detect bridge activity
        let fileModTime = (try? FileManager.default.attributesOfItem(atPath: statusFilePath))?[.modificationDate] as? Date

        guard let content = try? String(contentsOfFile: statusFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        if content.hasPrefix("msg:") {
            let parts = String(content.dropFirst("msg:".count))
            // Format: "word" or "word:mode"
            let components = parts.split(separator: ":", maxSplits: 1)
            let word = String(components[0])
            let mode = components.count > 1 ? String(components[1]) : "thinking"

            if currentWord.isEmpty {
                spinnerFrameIndex = 0
                stalledIntensity = 0
                lastContentChangeTime = Date()
                log("Working: \(word) [\(mode)]")
            }

            // Reset stalled timer if the file was freshly written
            // (bridge writes every 300ms while spinner is active)
            if let modTime = fileModTime, modTime != lastFileModTime {
                lastContentChangeTime = Date()
                if stalledIntensity > 0 {
                    stalledIntensity = 0
                }
                lastFileModTime = modTime
            }

            if word != currentWord || mode != currentMode {
                currentWord = word
                currentMode = mode
            }
        } else if content == "idle" {
            if !currentWord.isEmpty {
                currentWord = ""
                currentMode = "idle"
                stalledIntensity = 0
                label.updateContent("  Claude Ready  ", color: idleTextColor)
                log("Idle")
            }
            lastFileModTime = fileModTime
        }
    }

    private func updateStalledColor() {
        guard !currentWord.isEmpty else { return }

        // Match Claude Code's stalled detection:
        // - After 3s with no new content: start going red
        // - stalledIntensity ramps 0→1 over next 2s (3s to 5s)
        // - Smooth easing: intensity += (target - intensity) * 0.1 per 50ms tick
        let elapsed = Date().timeIntervalSince(lastContentChangeTime)
        let targetIntensity: CGFloat
        if elapsed > 3.0 {
            targetIntensity = min(CGFloat((elapsed - 3.0) / 2.0), 1.0)
        } else {
            targetIntensity = 0
        }

        // Smooth easing toward target (matches Claude Code's easing)
        let diff = targetIntensity - stalledIntensity
        if abs(diff) < 0.01 {
            stalledIntensity = targetIntensity
        } else {
            stalledIntensity += diff * 0.1
        }
    }

    private func spinnerTick() {
        guard !currentWord.isEmpty else { return }
        spinnerFrameIndex = (spinnerFrameIndex + 1) % spinnerFrames.count
        let spinner = spinnerFrames[spinnerFrameIndex]

        // Compute color based on mode and stalled state
        let color: NSColor
        if stalledIntensity > 0 {
            // Stalled: interpolate claude → red based on intensity
            color = lerpColor(claudeColor, stalledColor, stalledIntensity)
        } else if currentMode == "tool-use" || currentMode == "tool-input" {
            // Tool use: use shimmer color
            color = shimmerColor
        } else {
            // Normal: claude theme color
            color = claudeColor
        }

        label.updateContent("  \(spinner)\t\(currentWord)…  ", color: color)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = TouchBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("App launched")
        controller.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DFRElementSetControlStripPresenceForIdentifier(TouchBarController.stripIdentifier, false)
        return .terminateNow
    }
}

// MARK: - Main

log("Starting ClaudeTouchBar...")
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
