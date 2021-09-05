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
            List(content: {
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
                    Label("Tags", systemImage:"tag")
                }.frame(height: 28)
                NavigationLink(destination: DesignContentView()) {
                    Label("Design", systemImage:"wand.and.stars")
                }.frame(height: 28)
                Divider()
                NavigationLink(destination: AdvanceContentView()) {
                    Label("Advance", systemImage:"hammer")
                }.frame(height: 28)
               
            })
            .listStyle(SidebarListStyle())
            .frame(minWidth:200, maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)
            .onAppear(perform: {
                
            })
        }
        
    }
}


