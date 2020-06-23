//
//  IHavenContext.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/23.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
class IHavenContext: ObservableObject {
    @Published var currentState: ViewState = .Main
}
