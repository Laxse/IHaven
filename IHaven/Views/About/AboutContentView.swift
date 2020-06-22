//
//  AboutContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/22.
//  Copyright © 2020 梁霄. All rights reserved.
//
 
import SwiftUI

struct AboutContentView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Image("MenuBarIcon").resizable().scaledToFit().frame(height: 60)
            Text("IHaven").font(.headline).fontWeight(.regular)
            Text("Version 0.0.1(beta)")
                .fontWeight(.ultraLight).font(.system(size: 12))
            Text("Copyright © 2020-2020 Laxse").font(.system(size: 10))
                .fontWeight(.ultraLight)
        }.frame( maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutContentView_Previews: PreviewProvider {
    static var previews: some View {
        AboutContentView()
    }
}
