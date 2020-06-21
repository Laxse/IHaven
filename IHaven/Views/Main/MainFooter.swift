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
            Spacer()
            SettingBtn()
        }
    }
}

/**
 * 查询条件按钮
 */
struct SettingBtn: View {
    static var SettingBtnWidth:CGFloat = 50.0
    var body : some View{
        HStack(){
            Text("Made With").foregroundColor(Color.purple)
            Text("❤").foregroundColor(Color.red)
            Text("By Laxse ").foregroundColor(Color.purple)
            Spacer()
            Button(action: {
            }){
                Image(nsImage: NSImage(named: "PreferencesButtonIcon")!)
            }.frame(width: SettingBtn.SettingBtnWidth, height: SettingBtn.SettingBtnWidth)
                .buttonStyle(PlainButtonStyle())
                .contextMenu{
                    Button(action: {
                    }) {
                        Text("Choose Country")
                    }
                    
                    Button(action: {
                        NSApplication.shared.terminate(self)
                    }) {
                        Text("Detect Location")
                    }
            }
        }
        
    }
}
