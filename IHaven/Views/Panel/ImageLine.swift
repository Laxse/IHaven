//
//  ImageLine.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/21.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation

class ImageLine:Identifiable {
    let uuid = UUID()
    var left:WallHavenImage?
    var right:WallHavenImage?
    init(left:WallHavenImage?,right:WallHavenImage?) {
        self.left = left
        self.right = right
    }
}
