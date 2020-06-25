//
//  ContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/9.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

//struct ContentView: View {
//    /* currentView用来控制当前显示页面 */
//    @EnvironmentObject var iHavenContext: IHavenContext
//
//    var body: some View {
//
//        ZStack{
//            VStack{
//                if(iHavenContext.currentState == .Main){
//                    MainContentView()
//                        .edgesIgnoringSafeArea(.all)
//                        .background(Color.black.opacity(0.5))
//                        .frame(maxWidth: .infinity, maxHeight: .infinity)
//                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
//
//                }
//                if(iHavenContext.currentState == .Filter){
//                    FilterContentView()
//                        .edgesIgnoringSafeArea(.all)
//                        .background(Color.black.opacity(0.5))
//                        .frame(maxWidth: .infinity, maxHeight: .infinity)
//                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
//
//                }
//            }
//
//            //            LoadingPanel()
//        }.frame(width: AppDelegate.shared?.popoverWidth, height: AppDelegate.shared?.popoverHeight)
//    }
//
//}


struct View2: View {
    @Binding var push: Bool
    
    var body: some View {
        ZStack {
            Color.yellow
            Button(action: {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.push.toggle()
                }
            }) {
                Text("POP")
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct View1: View {
    @Binding var push: Bool
    
    var body: some View {
        ZStack {
            Color.green
            Button(action: {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.push.toggle()
                }
            }) {
                Text("PUSH")
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView: View {
    //    /* currentView用来控制当前显示页面 */
    @EnvironmentObject var iHavenContext: IHavenContext
    
     @State private var push = false

    var body: some View {
        ZStack {
            if iHavenContext.currentState == .Main {
                MainContentView()
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    .edgesIgnoringSafeArea(.all)
                    .background(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if iHavenContext.currentState == .Filter {
                FilterContentView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    .edgesIgnoringSafeArea(.all)
                    .background(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
