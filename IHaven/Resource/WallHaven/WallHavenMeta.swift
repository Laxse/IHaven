//
//  WallHavenMeta.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/17.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
struct WallHavenMeta: Codable {
    let currentPage: Int?
    let lastPage: Int?
    let perPage: Int?
    let total: Int?
    let query: String? //TODO: Specify the type to conforms Codable protocol
    let seed: String? //TODO: Specify the type to conforms Codable protocol
    private enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
        case perPage = "per_page"
        case total
        case query
        case seed
    }
}
