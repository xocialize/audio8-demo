//
//  AppDelegate.swift
//  Audio8 Demo — reference & metrics harness for Audio8-TTS-Preview-0.6b.
//
//  Code-only AppKit shell (no IB) hosting the SwiftUI interface, matching the house
//  bootstrap in main.swift.
//
//  The template's Metal/DisplayLink startup (AppManager.initApp) is deliberately NOT
//  called: this app renders no Metal surface of its own, and an idle DisplayLink would
//  show up in the very timing and memory numbers the app exists to measure. AppManager
//  stays in the target unused rather than being deleted, so the template stays intact
//  for the next app copied from it.
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
