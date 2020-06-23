//
//  Header.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/12.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct MainHeader: View {
    @ObservedObject var imageRepository:ImageRepository
    var body: some View {
        HStack(alignment: .center) {
            RandomBtn(imageRepository: imageRepository)
            Spacer()
            Text("IHaven")
                .font(.title)
                .fontWeight(.ultraLight)
                .foregroundColor(Color.purple)
                .multilineTextAlignment(.center)
            Spacer()
            FilterBtn()
        }.padding(.horizontal,10).padding(.vertical, 3).background(Color.black.opacity(0.5))
    }
}
/**
 * 查询条件按钮
 */
struct RandomBtn: View {
    static var RandomBtnWidth:CGFloat = 18.0
    @ObservedObject var imageRepository:ImageRepository
    var body : some View{
        Button(action: {
            self.imageRepository.clean()
            self.imageRepository.load(succCallBack: {}) {}
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
            self.iHavenContext.currentState = .Filter
        }){
            Image(nsImage: NSImage(named: "FilterBtn")!).resizable()
        }
        .frame(width: FilterBtn.FilterBtnWidth, height: FilterBtn.FilterBtnWidth)
        .buttonStyle(PlainButtonStyle())
    }
}
