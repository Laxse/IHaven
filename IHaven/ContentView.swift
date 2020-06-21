//
//  ContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/9.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    /* currentView用来控制当前显示页面 */
    //    @State private var currentView: ViewState = .Main
    var body: some View {
        VStack{
            MainContentView()
                .edgesIgnoringSafeArea(.all)
                .background(Color.black.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
}

