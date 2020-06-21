//
//  QueryResponse.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/15.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation

struct QueryResponse: Codable {

    let data: [WallHavenImage]
    let meta: WallHavenMeta
}
