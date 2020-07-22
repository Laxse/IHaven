//
//  AdvanceDesktopWindowController.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/17.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
import AppKit
import SwiftUI
class DesktopWindowController: NSWindowController{
        
    init() {
        
        let iHavenDesktop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 630), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,.texturedBackground], backing: .buffered, defer: false)
        iHavenDesktop.center()
        iHavenDesktop.isOpaque = false
        iHavenDesktop.titlebarAppearsTransparent = true
        iHavenDesktop.titleVisibility = .hidden
        //实现自定义标题栏
        let iHavenToolbar = NSToolbar()
        iHavenToolbar.showsBaselineSeparator = false
        iHavenDesktop.toolbar = iHavenToolbar

        iHavenDesktop.contentView = NSHostingView(rootView: DesktopContentView().edgesIgnoringSafeArea(.all).frame(maxWidth: .infinity, maxHeight: .infinity))
        super.init(window: iHavenDesktop)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
