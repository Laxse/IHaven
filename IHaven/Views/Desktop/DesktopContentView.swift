//
//  SettingContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/14.
//  Copyright © 2020 梁霄. All rights reserved.
//


import SwiftUI

struct DesktopContentView: View {
    @State var query:String = "";
    
    var body: some View {
        NavigationView {
            SideBar().frame(minWidth: 200, maxWidth: 200)
            LatestContentView()
        }
    }
}

struct SideBar: View {
    var body: some View {
            List() {
                // 保留空白区域
                NavigationLink(destination: LatestContentView()) {
                    Label("Latest", systemImage:"timer")
                }.frame(height: 32)
                NavigationLink(destination: ToplistContentView()) {
                   Label("Toplist", systemImage:"rosette")
                }.frame(height: 32)
                NavigationLink(destination: RandomContentView()) {
                    Label("Random", systemImage:"arrow.branch")
                }.frame(height: 32)
                NavigationLink(destination: UploadContentView()) {
                    Label("Upload", systemImage:"icloud.and.arrow.up")
                }.frame(height: 32)
                NavigationLink(destination: DesignContentView()) {
                    Label("Design", systemImage:"wand.and.stars")
                }.frame(height: 32)
                NavigationLink(destination: AdvanceContentView()) {
                    Label("Advance", systemImage:"hammer")
                }.frame(height: 32)
            }
            .listStyle(SidebarListStyle())
            .listRowBackground(Image(systemName: "sparkles"))
    }
}


//
//struct DesktopContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            DesktopContentView(query: "Hello, World!")
//        }
//    }
//}
//
//VStack{
//    HStack {
//        TextField("搜索", text: $query)
//        .textFieldStyle(RoundedBorderTextFieldStyle())
//    }.padding(.horizontal, 20).padding(.vertical, 15)
//    List() {
//        // 保留空白区域
//
//        NavigationLink(destination: LatestContentView()) {
//            Text("Latest").font(.system(size: 20)).fontWeight(.regular)
//        }.frame(height: 42)
//        NavigationLink(destination: ToplistContentView()) {
//            Text("Toplist").font(.system(size: 20)).fontWeight(.regular)
//        }.frame(height: 42)
//        NavigationLink(destination: RandomContentView()) {
//            Text("Random").font(.system(size: 20)).fontWeight(.regular)
//        }.frame(height: 42)
//        NavigationLink(destination: UploadContentView()) {
//            Text("Upload").font(.system(size:20)).fontWeight(.regular)
//        }.frame(height: 42)
//        NavigationLink(destination: DesignContentView()) {
//            Text("Design").font(.system(size: 20)).fontWeight(.regular)
//        }.frame(height: 42)
//        NavigationLink(destination: AdvanceContentView()) {
//            Text("Advance").font(.system(size: 20)).fontWeight(.regular)
//        }.frame(height: 42)
//        }
//    .listStyle(SidebarListStyle())
//}.frame(minWidth: 220, maxWidth: 220, maxHeight: .infinity)
