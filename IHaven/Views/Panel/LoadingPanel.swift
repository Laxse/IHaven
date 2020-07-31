//
//  LoadingPanel.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/25.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct LoadingPanel: View {
    @State var animateTrimPath = false
    @State var rotateInfinity = false
    var body: some View {
        ZStack{
            Path{ path in
                path.addLines([
                    .init(x: 2, y: 1),
                    .init(x: 1, y: 0),
                    .init(x: 0, y: 1),
                    .init(x: 1, y: 2),
                    .init(x: 3, y: 0),
                    .init(x: 4, y: 1),
                    .init(x: 3, y: 2),
                    .init(x: 2, y: 1),
                ])
            }
            .trim(from: animateTrimPath ? 1/0.99 : 0, to: animateTrimPath ? 1/0.99 : 1)
            .scale(50, anchor: .topLeading)
            .stroke(Color.purple,lineWidth: 6)
            .offset(x: 100, y: 350)
            animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true))
                .onAppear(){
                    self.animateTrimPath.toggle()
            }
        }
        .rotationEffect(.degrees(rotateInfinity ? 0 : -360))
        .scaleEffect(0.3, anchor: .center)
        .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false))
        .onAppear(){
            self.rotateInfinity.toggle()
        }
    }
}
