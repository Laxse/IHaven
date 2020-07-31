//
//  LatestContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct LatestContentView: View {
    @State var txt:String = "123"
    var body: some View {
        VStack {
           

                TextField("123", text: $txt)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LatestContentView_Previews: PreviewProvider {
    static var previews: some View {
        LatestContentView()
    }
}
