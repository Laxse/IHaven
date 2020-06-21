//
//  FilterHeader.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct FilterHeader: View {
    @Binding var currentView: ViewState
    var body: some View {
        HStack{
            FilterBackBtn(currentView: $currentView)
            Spacer()
        }
    }
}
/**
 * 查询条件按钮
 */
struct FilterBackBtn: View {
    static var FilterBtnWidth:CGFloat = 25.0
    @Binding var currentView: ViewState
    var body : some View{
        Button(action: {
            self.currentView = .Main
        }){
            Image(nsImage: NSImage(named: "BackButton")!)
        }
        .frame(width: FilterBackBtn.FilterBtnWidth, height: FilterBackBtn.FilterBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}
