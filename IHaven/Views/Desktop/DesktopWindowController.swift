//
//  DesktopWindowController.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/17.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class DesktopWindowController: NSWindowController {

    init() {
        let iHavenDesktop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        iHavenDesktop.center()
        iHavenDesktop.isOpaque = false
        iHavenDesktop.titlebarAppearsTransparent = true
        iHavenDesktop.titleVisibility = .hidden
        //实现自定义标题栏
        iHavenDesktop.toolbar = NSToolbar()
        iHavenDesktop.contentView = NSHostingView(rootView: DesktopContentView()
            .environmentObject(AppDelegate.shared!.iHavenContext)
            .ignoresSafeArea(.all)
            .frame(minWidth: 1000, minHeight: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity))

        //      窗口关闭通知，隐藏Dock的图标，程序转变为Agent //暂不隐藏
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: iHavenDesktop, queue: .main) { _ in
            MainActor.assumeIsolated {
                _ = NSApp.setActivationPolicy(.accessory)
            }
        }
        super.init(window: iHavenDesktop)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}