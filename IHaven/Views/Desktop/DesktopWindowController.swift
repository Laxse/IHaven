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
class DesktopWindowController: NSWindowController {
    init() {
      
       let iHavenDesktop = DesktopWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.closable,.titled], backing: .buffered, defer: false)
        iHavenDesktop.setFrameAutosaveName("IHaven")
        iHavenDesktop.contentView = NSHostingView(rootView: DesktopContentView())
        iHavenDesktop.center()
        iHavenDesktop.title = "IHaven"
        super.init(window: iHavenDesktop)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
