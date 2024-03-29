//
//  Footer.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct MainFooter: View {
    var body: some View {
        HStack(alignment: .center) {
            Text("Made With").foregroundColor(Color.purple)
            Text("❤").foregroundColor(Color.red)
            Text("By Laxse ").foregroundColor(Color.purple)
            Spacer()
            Button(action: {
                AppDelegate.shared?.showDesktopWindow()
            }) {
                Text("高级模式")
            }
            SettingBtn()
        }.frame(height: 40).padding(.horizontal, 10)
    }
}

/**
 * 查询条件按钮
 */
struct SettingBtn: View {
    static var SettingBtnWidth:CGFloat = 25.0
    var body : some View{
        MenuButton(label: Image("PreferencesButtonIcon")
            .frame(width: SettingBtn.SettingBtnWidth, height: SettingBtn.SettingBtnWidth)) {
                Button(action: {
                    AppDelegate.shared?.showAboutWindow()
                }) {
                    Text("About IHaven")
                }
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Laxse/IHaven")!)
                }) {
                    Text("Send Feedback...")
                }
                Button(action: {
                   // 哭了哭了
                }) {
                    Text("我好卑微啊～")
                }
                Button(action: {
                    NSApplication.shared.terminate(self)
                }) {
                    Text("Quit")
                }
        }
        .frame(width: SettingBtn.SettingBtnWidth, height: SettingBtn.SettingBtnWidth)
        .menuButtonStyle(BorderlessButtonMenuButtonStyle())
    }
}
