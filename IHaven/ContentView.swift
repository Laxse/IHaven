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
    @EnvironmentObject var iHavenContext: IHavenContext
    
    var body: some View {
        VStack{
            if(iHavenContext.currentState == .Main){
            MainContentView()
                    .edgesIgnoringSafeArea(.all)
                    .background(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if(iHavenContext.currentState == .Filter){
            FilterContentView()
                    .edgesIgnoringSafeArea(.all)
                    .background(Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
        }
    }
    
}

