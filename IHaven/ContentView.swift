//
//  ContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/9.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI


struct ContentView: View {
    //    /* currentView用来控制当前显示页面 */
    @EnvironmentObject var iHavenContext: IHavenContext
    //未研究ViewBuilder的作用，能防止precondition failure: attribute failed to set an initial value: 87
    //@see https://stackoverflow.com/questions/60028961/swiftui-crash-precondition-failure-attribute-failed-to-set-an-initial-value
    @ViewBuilder
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
