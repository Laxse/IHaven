//
//  SettingContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/14.
//  Copyright © 2020 梁霄. All rights reserved.
//

 
import SwiftUI

struct DesktopContentView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Image("AppImage").resizable().scaledToFit().frame(height: 60)
            Text("IHaven").font(.headline).fontWeight(.regular)
            Text("Version 0.0.1(beta)")
                .fontWeight(.ultraLight).font(.system(size: 12))
            Text("Copyright © 2020-2020 Laxse").font(.system(size: 10))
                .fontWeight(.ultraLight)
        }.frame( maxWidth: .infinity, maxHeight: .infinity)
    }
}

