//
//  RandomContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct RandomContentView: View {
    var body: some View {
        VStack {
                   Text("Hello, World! RandomContentView")
               }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RandomContentView_Previews: PreviewProvider {
    static var previews: some View {
        RandomContentView()
    }
}
