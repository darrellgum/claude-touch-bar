import AppKit
import Foundation

let statusFilePath = "/tmp/claude-touchbar-status"

let spinnerFrames: [Character] = ["·","✢","✳","✶","✻","✽"]

// Claude Code theme colors (dark mode) — extracted from binary
let claudeColor = NSColor(red: 215.0/255, green: 119.0/255, blue: 87.0/255, alpha: 1)
let claudeShimmerColor = NSColor(red: 245.0/255, green: 149.0/255, blue: 117.0/255, alpha: 1)
let stalledColor = NSColor(red: 171.0/255, green: 43.0/255, blue: 63.0/255, alpha: 1)
// Tool use base and shimmer
let toolColor = NSColor(red: 235.0/255, green: 159.0/255, blue: 127.0/255, alpha: 1)
let toolShimmerColor = NSColor(red: 255.0/255, green: 189.0/255, blue: 157.0/255, alpha: 1)
// System/compacting: claudeBlue
let systemBlueColor = NSColor(red: 87.0/255, green: 105.0/255, blue: 247.0/255, alpha: 1)
let systemBlueShimmerColor = NSColor(red: 117.0/255, green: 135.0/255, blue: 255.0/255, alpha: 1)
// Idle
let idleTextColor = NSColor(red: 102.0/255, green: 102.0/255, blue: 102.0/255, alpha: 1)
let idleShimmerColor = NSColor(red: 142.0/255, green: 142.0/255, blue: 142.0/255, alpha: 1)
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
    var attributedText: NSAttributedString? { didSet { needsDisplay = true } }
    var plainText: String = "  Claude Ready  " { didSet { needsDisplay = true } }
    var plainColor: NSColor = idleTextColor { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    private let font = NSFont.systemFont(ofSize: 15, weight: .medium)

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
        let size: NSSize
        if let attrText = attributedText {
            size = attrText.size()
        } else {
            let attr: [NSAttributedString.Key: Any] = [.font: font]
            size = (plainText as NSString).size(withAttributes: attr)
        }
        return NSSize(width: size.width + 16, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        bounds.fill()

        if let attrText = attributedText {
            let size = attrText.size()
            let x = (bounds.width - size.width) / 2
            let y = (bounds.height - size.height) / 2
            attrText.draw(at: NSPoint(x: x, y: y))
        } else {
            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: plainColor
            ]
            let size = (plainText as NSString).size(withAttributes: attr)
            let x = (bounds.width - size.width) / 2
            let y = (bounds.height - size.height) / 2
            (plainText as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attr)
        }
    }

    func updatePlain(_ text: String, color: NSColor) {
        attributedText = nil
        plainText = text
        plainColor = color
        invalidateIntrinsicContentSize()
    }

    func updateAttributed(_ attrStr: NSAttributedString) {
        attributedText = attrStr
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
    private var currentTokenCount: String = ""  // tracks token counter for activity detection
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
        // Main animation tick at 50ms (matches Claude Code's shimmer interval)
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.animationTick()
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

    private func checkStatusFile() {
        guard let content = try? String(contentsOfFile: statusFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        if content.hasPrefix("msg:") {
            let parts = String(content.dropFirst("msg:".count))
            // Format: "word:mode" or "word:mode:tokencount"
            let components = parts.split(separator: ":", maxSplits: 2)
            let word = String(components[0])
            let mode = components.count > 1 ? String(components[1]) : "thinking"
            let tokenCount = components.count > 2 ? String(components[2]) : ""

            if currentWord.isEmpty {
                spinnerFrameIndex = 0
                stalledIntensity = 0
                lastContentChangeTime = Date()
                log("Working: \(word) [\(mode)]")
            }

            // Reset stalled when any activity indicator changes:
            // - word change (new spinner word = new content)
            // - mode change (e.g. thinking → tool-use)
            // - token count change (tokens flowing even with same word)
            let activityChanged = word != currentWord
                || mode != currentMode
                || (!tokenCount.isEmpty && tokenCount != currentTokenCount)

            if activityChanged {
                lastContentChangeTime = Date()
                stalledIntensity = 0
                currentWord = word
                currentMode = mode
                currentTokenCount = tokenCount
            }
        } else if content == "idle" {
            if !currentWord.isEmpty {
                currentWord = ""
                currentMode = "idle"
                stalledIntensity = 0
                label.updatePlain("  Claude Ready  ", color: idleTextColor)
                log("Idle")
            }
        }
    }

    // Animation state
    private var tickCount: Int = 0
    private var spinnerTickAccum: Int = 0

    private func animationTick() {
        tickCount += 1

        // Update stalled intensity every tick (50ms, matches Claude Code)
        updateStalledIntensity()

        guard !currentWord.isEmpty else { return }

        // Spinner character changes every 5 ticks (250ms)
        spinnerTickAccum += 1
        if spinnerTickAccum >= 5 {
            spinnerTickAccum = 0
            spinnerFrameIndex = (spinnerFrameIndex + 1) % spinnerFrames.count
        }

        renderTouchBar()
    }

    private func updateStalledIntensity() {
        guard !currentWord.isEmpty else { return }
        let elapsed = Date().timeIntervalSince(lastContentChangeTime)
        let targetIntensity: CGFloat
        if elapsed > 3.0 {
            targetIntensity = min(CGFloat((elapsed - 3.0) / 2.0), 1.0)
        } else {
            targetIntensity = 0
        }
        let diff = targetIntensity - stalledIntensity
        if abs(diff) < 0.01 {
            stalledIntensity = targetIntensity
        } else {
            stalledIntensity += diff * 0.1
        }
    }

    private func renderTouchBar() {
        let spinner = spinnerFrames[spinnerFrameIndex]
        let displayText = "\(currentWord)…"
        let textLen = displayText.count

        // Determine base and shimmer colors for current state
        let baseColor: NSColor
        let glimmerColor: NSColor

        if stalledIntensity > 0 {
            // Stalled: no shimmer, just the stalled color
            let color = lerpColor(claudeColor, stalledColor, stalledIntensity)
            let fullText = "  \(spinner)\t\(displayText)  "
            let attr = NSAttributedString(string: fullText, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: color
            ])
            label.updateAttributed(attr)
            return
        } else if currentMode == "system" {
            baseColor = systemBlueColor
            glimmerColor = systemBlueShimmerColor
        } else if currentMode == "tool-use" || currentMode == "tool-input" {
            baseColor = toolColor
            glimmerColor = toolShimmerColor
        } else {
            baseColor = claudeColor
            glimmerColor = claudeShimmerColor
        }

        if currentMode == "tool-use" || currentMode == "tool-input" || currentMode == "system" {
            // Tool-use: whole-text sine pulse between base and shimmer
            // flashOpacity = (sin(time/1000 * PI) + 1) / 2  at 50ms ticks
            let timeMs = Double(tickCount) * 50.0
            let flash = CGFloat((sin(timeMs / 1000.0 * .pi) + 1.0) / 2.0)
            let color = lerpColor(baseColor, glimmerColor, flash)
            let fullText = "  \(spinner)\t\(displayText)  "
            let attr = NSAttributedString(string: fullText, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: color
            ])
            label.updateAttributed(attr)
        } else {
            // Thinking/responding: 3-char-wide glimmer sweep across the word
            // Sweep speed: 1 position per 200ms (4 ticks). Cycle = textLen + 20
            let cycleLen = textLen + 20
            // Sweep goes right-to-left in responding, left-to-right otherwise
            let glimmerIndex: Int
            if currentMode == "responding" {
                glimmerIndex = textLen + 10 - (tickCount / 4) % cycleLen
            } else {
                glimmerIndex = (tickCount / 4) % cycleLen - 10
            }

            // Build attributed string: prefix + spinner + tab + per-char word + suffix
            let result = NSMutableAttributedString()
            let font = NSFont.systemFont(ofSize: 15, weight: .medium)

            // Leading space + spinner (always base color)
            result.append(NSAttributedString(string: "  \(spinner)\t", attributes: [
                .font: font, .foregroundColor: baseColor
            ]))

            // Per-character coloring for the word
            for (i, char) in displayText.enumerated() {
                let dist = abs(i - glimmerIndex)
                let color = dist <= 1 ? glimmerColor : baseColor
                result.append(NSAttributedString(string: String(char), attributes: [
                    .font: font, .foregroundColor: color
                ]))
            }

            // Trailing space
            result.append(NSAttributedString(string: "  ", attributes: [
                .font: font, .foregroundColor: baseColor
            ]))

            label.updateAttributed(result)
        }
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
