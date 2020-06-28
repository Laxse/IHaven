//
//  CheckableButton.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/28.
//  Copyright © 2020 梁霄. All rights reserved.
//
//  可点击按钮 拥有点击状态，可设置选中/未选中状态的前景色和背景色

import SwiftUI

struct CheckableButton: View {
    var lable:String
    var unclickFontColor:Color
    var clickFontColor:Color
    var unclickBackColor:Color
    var clickBackColor:Color
    var clickCallBack:(Bool)-> Void
    @State var checked:Bool
    
    var body: some View{
        Button(action: {
            self.checked.toggle()
            self.clickCallBack(self.checked)
        }) {
            Text(lable)
        }
        .buttonStyle(checked ? CheckedButtonStyle(fontColor: clickFontColor) : CheckedButtonStyle(fontColor: unclickFontColor))
        .frame(width: 80, height: 30, alignment: .center)
        .background(checked ? clickBackColor : unclickBackColor)
        .cornerRadius(2.0)
    }
}
struct CheckedButtonStyle: ButtonStyle{
    var fontColor:Color
    func makeBody(configuration: CheckedButtonStyle.Configuration) -> some View {
        configuration.label.foregroundColor(fontColor)
    }
}
