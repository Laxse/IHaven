//
//  FilterHeader.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct FilterHeader: View {
    var body: some View {
        HStack{
            FilterBackBtn()
            Spacer()
        }
    }
}
/**
 * 查询条件按钮
 */
struct FilterBackBtn: View {
    static var FilterBtnWidth:CGFloat = 25.0
    @EnvironmentObject var iHavenContext: IHavenContext
    var body : some View{
        Button(action: {
            self.iHavenContext.currentState = .Main
        }){
            Image(nsImage: NSImage(named: "TagBtn")!)
        }
        .frame(width: FilterBackBtn.FilterBtnWidth, height: FilterBackBtn.FilterBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}
