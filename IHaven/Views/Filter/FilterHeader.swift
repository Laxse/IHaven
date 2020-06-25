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
        HStack(alignment: .center){
            FilterBackBtn()
            Spacer()
        }
        .padding(.vertical,7)
        .padding(.horizontal,6)
        .frame(height: 40)
        .background(Color.black)
    }
}
/**
 * 查询条件按钮
 */
struct FilterBackBtn: View {
    static var FilterBtnWidth:CGFloat = 16.0
    @EnvironmentObject var iHavenContext: IHavenContext
    var body : some View{
        Button(action: {
            withAnimation(.easeOut(duration: 0.3)) {
                self.iHavenContext.currentState = .Main
            }
        }){
            Image(nsImage: NSImage(named: "BackBtn")!).resizable()
        }
        .frame(width: FilterBackBtn.FilterBtnWidth * 2, height: FilterBackBtn.FilterBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}
