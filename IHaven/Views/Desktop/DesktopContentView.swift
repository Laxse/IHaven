//
//  SettingContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/14.
//  Copyright © 2020 梁霄. All rights reserved.
//


import SwiftUI

struct DesktopContentView: View {
    
    var body: some View {
        NavigationView {
            List{
                NavigationLink(destination: LatestContentView() ) {
                    Label("Latest", systemImage:"timer")
                }.frame(height: 28)
                NavigationLink(destination: ToplistContentView()) {
                   Label("Toplist", systemImage:"rosette")
                }.frame(height: 28)
                NavigationLink(destination: RandomContentView()) {
                    Label("Random", systemImage:"arrow.branch")
                }.frame(height: 28)
                NavigationLink(destination: UploadContentView()) {
                    Label("Upload", systemImage:"icloud.and.arrow.up")
                }.frame(height: 28)
                NavigationLink(destination: DesignContentView()) {
                    Label("Design", systemImage:"wand.and.stars")
                }.frame(height: 28)
//                Spacer()
//                Divider()
                NavigationLink(destination: AdvanceContentView()) {
                    Label("Advance", systemImage:"hammer")
                }
                .frame(height: 28)
               
            }.listStyle(SidebarListStyle())
            .ignoresSafeArea(edges: .all)
            .frame(minWidth: 200, maxWidth: 200,  alignment: .leading)
            LatestContentView()
        }
        
    }
}


