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
            VStack {
                HStack {
                    TextField("搜索", text: $query)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                .padding(.horizontal, 20).padding(.vertical, 15)
                List() {
                    // 保留空白区域
                    NavigationLink(destination: LatestContentView()) {
                        Text("Latest").font(.system(size: 20)).fontWeight(.regular)
                        }.frame(height: 42)
                    NavigationLink(destination: ToplistContentView()) {
                        Text("Toplist").font(.system(size: 20)).fontWeight(.regular)
                    }.frame(height: 42)
                    NavigationLink(destination: RandomContentView()) {
                        Text("Random").font(.system(size: 20)).fontWeight(.regular)
                        }.frame(height: 42)
                    NavigationLink(destination: UploadContentView()) {
                        Text("Upload").font(.system(size: 20)).fontWeight(.regular)
                    }.frame(height: 42)
                    NavigationLink(destination: DesignContentView()) {
                        Text("Design").font(.system(size: 20)).fontWeight(.regular)
                    }.frame(height: 42)
                    NavigationLink(destination: AdvanceContentView()) {
                        Text("Advance").font(.system(size: 20)).fontWeight(.regular)
                        }.frame(height: 42)
                    }
                .listStyle(SidebarListStyle())
            }.frame(minWidth: 220, maxWidth: 220)
            //.accentColor(.gray)
            //TODO how can i deal with it
            //1. 'accentColor' has been explicitly marked unavailable here (SwiftUI.View)
            //Need macOS 11+
            //Desktop maybe delay
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
    }
}


struct DesktopContentView_Previews: PreviewProvider {
    static var previews: some View {
        DesktopContentView(query: "Hello, World!")
    }
}
