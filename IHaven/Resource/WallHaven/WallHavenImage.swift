//
//  ImageData.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/17.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation

struct WallHavenImage: Codable, Hashable,Identifiable{
    static func == (lhs: WallHavenImage, rhs: WallHavenImage) -> Bool {
        return lhs.id == rhs.id
    }
    let id: String
    let url: URL
    let shortUrl: URL
    let views: Int
    let favorites: Int
    let source: String
    let purity: String
    let category: String
    let dimensionX: Int
    let dimensionY: Int
    let resolution: String
    let ratio: String
    let fileSize: Int
    let fileType: String
    let createdAt: String
    let colors: [String]
    let path: URL
    struct Thumbs: Codable,Hashable {
        let large: URL
        let original: URL
        let small: URL
    }
    let thumbs: Thumbs
    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case shortUrl = "short_url"
        case views
        case favorites
        case source
        case purity
        case category
        case dimensionX = "dimension_x"
        case dimensionY = "dimension_y"
        case resolution
        case ratio
        case fileSize = "file_size"
        case fileType = "file_type"
        case createdAt = "created_at"
        case colors
        case path
        case thumbs
    }
}
