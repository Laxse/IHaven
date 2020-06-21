//
//  AppDelegate.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/9.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
//    static var shared:AppDelegate?
    var popover: NSPopover!
    var statusBarItem: NSStatusItem!
    
    override init() {
        
        super.init()
//        AppDelegate.shared = self;
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        
        // Create the status item
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        
        if let button = self.statusBarItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.action = #selector(togglePopover(_:))
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = self.statusBarItem.button {
            if self.popover.isShown {
                self.popover.performClose(sender)
            } else {
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
}
