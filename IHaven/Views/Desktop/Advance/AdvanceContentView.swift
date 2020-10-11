//
//  AdvanceContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct AdvanceContentView: View {
    var body: some View {
        ZStack {
//            VStack {
//                HStack(alignment: .center) {
//                    Rectangle().frame(width: 300, height: 300).background(Color.green)
//                    Spacer()
//                }
//                Spacer()
//                HStack {
//                    Spacer()
//                    Rectangle().frame(width: 300, height: 300).background(Color.yellow)
//                }
//            }
              Rectangle().frame(width: 300, height: 300).background(Color.green)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AdvanceContentView_Previews: PreviewProvider {
    static var previews: some View {
        AdvanceContentView()
    }
}
