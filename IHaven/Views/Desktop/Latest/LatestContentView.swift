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
            ZStack(content: {
                HStack(alignment: .center) {
                    Spacer()
                    Pagination(count: 5000, size: 24, active: 1)
                        .padding(.trailing, 10)
                        .frame(maxHeight: .infinity)
                    
                }
            }).frame(maxWidth: .infinity, maxHeight: .infinity) .edgesIgnoringSafeArea(.all)
    }
}

struct LatestContentView_Previews: PreviewProvider {
    static var previews: some View {
        LatestContentView()
    }
}
