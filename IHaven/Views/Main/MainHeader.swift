//
//  Header.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/12.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct MainHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            RandomBtn()
            Spacer()
            Text("IHaven")
                .font(.title)
                .fontWeight(.ultraLight)
                .foregroundColor(Color.purple)
                .multilineTextAlignment(.center)
            Spacer()
            FilterBtn()
        }
        .padding(.horizontal,10)
        .padding(.vertical, 3)
    .frame(height: 40)
        .background(Color.black.opacity(0.5))
    }
}
/**
 * 查询条件按钮
 */
struct RandomBtn: View {
    static var RandomBtnWidth:CGFloat = 18.0
    var body : some View{
        Button(action: {
            ImageRepository.shared.clean();
            ImageRepository.shared.query.random()
            ImageRepository.shared.load(succCallBack: {}) {}
        }){
            Image(nsImage: NSImage(named: "RandomBtn")!).resizable()
        }
        .frame(width: RandomBtn.RandomBtnWidth, height: RandomBtn.RandomBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}

/**
 * 查询按钮
 */
struct FilterBtn: View {
    static var FilterBtnWidth:CGFloat = 18.0
    @EnvironmentObject var iHavenContext: IHavenContext
    var body : some View{
        Button(action: {
            withAnimation(.easeOut(duration: 0.3)) {
                self.iHavenContext.currentState = .Filter
            }
        }){
            Image(nsImage: NSImage(named: "FilterBtn")!).resizable()
        }
        .frame(width: FilterBtn.FilterBtnWidth, height: FilterBtn.FilterBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}
