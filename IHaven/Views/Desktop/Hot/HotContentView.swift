//
//  HotContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2021/9/7.
//  Copyright © 2021 梁霄. All rights reserved.
//

import SwiftUI
struct HotContentView: View {
    var repo = DImageRepository(query: QueryParameter(sorting: "hot"))
    var body: some View {
        QueryParameterContentView(repo: repo,message: "Our most popular wallpapers right now!",themeColor: Color.green)
    }
}
