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
    static var shared:AppDelegate?
    

    
    let popoverHeight:CGFloat = 500.0
    let popoverWidth:CGFloat = 400.0
    
    //window or view
    var iHavenPopover: NSPopover!
    var iHavenBarItem: NSStatusItem!
    lazy var aboutWindowController = AboutWindowController()
    lazy var desktopWindowController = DesktopWindowController()
    
    @ObservedObject var iHavenContext = IHavenContext()
    override init() {
        super.init()
        AppDelegate.shared = self;
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the popover
        iHavenPopover = NSPopover()
        iHavenPopover.contentSize = NSSize(width: popoverWidth, height: popoverHeight)
        iHavenPopover.behavior = .transient
        iHavenPopover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(iHavenContext))
        
        // Create the status item
        self.iHavenBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        
        if let button = self.iHavenBarItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.action = #selector(togglePopover(_:))
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func showAboutWindow() {
        aboutWindowController.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
    }
    func showDesktopWindow() {
        desktopWindowController.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        //default mode is Agent（info.plist）
        //when show Desktop window Dynactic change to show icon on dock
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = self.iHavenBarItem.button {
            if self.iHavenPopover.isShown {
                self.iHavenPopover.performClose(sender)
            } else {
                self.iHavenPopover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
}
