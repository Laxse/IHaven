//
//  QueryContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/14.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct QueryContentView: View {
    @Binding var currentView: ViewState
    var body: some View {
        VStack{
            QueryBackBtn(currentView: $currentView)
            Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
        }
    }
}

/**
 * 查询条件按钮
 */
struct QueryBackBtn: View {
    static var QueryBtnWidth:CGFloat = 25.0
    @Binding var currentView: ViewState
    var body : some View{
        Button(action: {
            self.currentView = .Main
        }){
            Image(nsImage: NSImage(named: "BackButton")!)
        }
        .frame(width: QueryBackBtn.QueryBtnWidth, height: QueryBackBtn.QueryBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}
