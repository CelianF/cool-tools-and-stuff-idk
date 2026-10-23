import AppKit
import SwiftUI

/// A Liquid Glass capsule at the top centre of the screen, just under the menu bar, like the system HUD.
enum HUD {
    private static let model = HUDModel()
    private static var hideWork: DispatchWorkItem?
    private static let panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above everything, full-screen apps included, like the system HUD.
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.overlayWindow)))
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let glass = NSGlassEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        glass.style = .clear
        glass.cornerRadius = 32
        glass.contentView = NSHostingView(rootView: HUDView(model: model))
        panel.contentView = glass
        roundFrame(of: panel, radius: 32)
        return panel
    }()

    static func show(symbol: String, title: String, level: Double? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(symbol: symbol, title: title, level: level) }
            return
        }
        guard AppSettings.shared.showHUD else { return }
        model.symbol = symbol
        model.title = title
        model.level = level
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 28))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }
}

@Observable
final class HUDModel {
    var symbol = ""
    var title = ""
    var level: Double?
}

private struct HUDView: View {
    let model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.symbol)
                .font(.system(size: 18, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24)
            if let level = model.level {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title).font(.system(size: 12, weight: .semibold))
                    GeometryReader { geo in
                        Capsule().fill(.primary.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.primary).frame(width: geo.size.width * level)
                            }
                    }
                    .frame(height: 6)
                    .animation(.snappy(duration: 0.15), value: level)
                }
            } else {
                Text(model.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 300, height: 64)
    }
}
