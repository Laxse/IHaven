//
//  RandomContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct RandomContentView: View {
    var repo = DImageRepository(query: QueryParameter(sorting: "random"))
    var body: some View {
        QueryParameterContentView(repo: repo,message: "Try your luck!",themeColor: Color.green)
    }
}
