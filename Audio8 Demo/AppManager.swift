//
//  AppManager.swift
//  MetalPreviewApp
//
//  Created by Dustin Nielson on 6/23/26.
//

import Foundation
import AppKit
import Metal
import OSLog
import LoggingKit


class AppManager: NSObject {
    
    internal var appInitializer: SequentialInitializer = .idle {
        didSet {
            if appInitializer != .stageComplete {
                elog.debug("App Initializer changed to: \(self.appInitializer.rawValue)")
            }
            do {
               try ExtendedInitializer(from: oldValue, to: appInitializer)
            } catch {
                elog.error("ExtendedInitializer failed: \(error.localizedDescription)")
                appInitializer = .fatalFailure
            }
        }
    }
    
    // MARK: - Metal References
    
    var metalDevice = MTLCreateSystemDefaultDevice()
    var metalCommandQueue: MTLCommandQueue?
    var shaderLibrary: MTLLibrary?

    
    var externalScreen: NSScreen? {
        didSet {}
    }
    
    
    // MARK: - DisplayLink (→ DisplayLink_initConfig.swift)
    
    internal var displayLink: CADisplayLink!
    internal var displayLinkRetryCount = 0
    internal let maxDisplayLinkRetries = 10
    
    // MARK: - Singleton
    
    private static var _shared: AppManager?
    private static let lock = NSLock()
    
    /// Thread-safe singleton accessor. Uses NSLock to guard first-time creation.
    static func shared() -> AppManager {
        lock.lock()
        defer { lock.unlock() }
        if _shared == nil {
            _shared = AppManager()
        }
        return _shared!
    }
    
    /// Resolves the Metal device and default shader library. Called once from shared().
    private override init() {
        super.init()
        
        guard let device = metalDevice else {
            elog.fault("No Metal device available")
            return
        }



        // 2. Create shared Metal command queue (used by TCE + all EnhancedMetalViews)
        metalCommandQueue = device.makeCommandQueue()



        elog.debug("Metal Infrastructure Initialized")
    }
    
    func initApp() {
        appInitializer = .displayLinkInit
    }
    
    
    
    // MARK: - Render Loop
    @objc internal func renderLoop() {
        autoreleasepool {}
    }
    
}
