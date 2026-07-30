//
//  AppDelegate.swift
//  Audio8 Demo — reference & metrics harness for Audio8-TTS-Preview-0.6b.
//
//  Code-only AppKit shell (no IB) hosting the SwiftUI interface, matching the house
//  bootstrap in main.swift.
//
//  The house template's Metal/DisplayLink startup has been removed rather than left
//  dormant: this app renders no Metal surface of its own, an idle DisplayLink would show
//  up in the very timing and memory numbers the app exists to measure, and dead scaffolding
//  in a reference app invites the reader to wonder what it is for.
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?
    /// The single engine owner for the app's lifetime (golden-path step 1).
    private let bench = Audio8Bench()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: Tokens.Layout.minWindowWidth,
                                height: Tokens.Layout.minWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Audio8 TTS — reference & metrics"
        window.contentView = NSHostingView(rootView: RootView(bench: bench))
        window.center()
        window.setFrameAutosaveName("Audio8DemoMain")
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
