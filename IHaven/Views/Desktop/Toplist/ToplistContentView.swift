//
//  ToplistContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct ToplistContentView: View {
    var repo = DImageRepository(query: QueryParameter(sorting: "toplist"))
    var body: some View {
        QueryParameterContentView(repo: repo)
    }
}
