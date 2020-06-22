//
//  AboutViewController.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
import AppKit
import SwiftUI
class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 160), styleMask: [.closable,.titled], backing: .buffered, defer: false)
        window.setFrameAutosaveName("About IHaven")
        window.center()
        window.contentView = NSHostingView(rootView: AboutContentView())
        super.init(window: window)
    }
    override func loadWindow() {
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
