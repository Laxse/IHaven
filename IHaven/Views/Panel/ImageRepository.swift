//
//  ImageSet.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/23.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
class ImageRepository: ObservableObject {
    @Published var images:[ImageLine] = []
    @Published var query:QueryParameter = QueryParameter()
    @Published var loading:Bool = false
    func clean() {
        self.images.removeAll()
    }
    
    func load(succCallBack: @escaping () -> Swift.Void,errorCallBack:  @escaping () -> Swift.Void) {
        WallHavenImageRepository.shared.query(parameters: query.toDictionary()) { result in
            switch result{
            case let .success(data):
                self.query.page = self.query.page + 1
                var imageLine = ImageLine(left: nil, right: nil)
                data.data.forEach { image in
                    if(imageLine.left==nil){
                        imageLine.left = image
                    }else if(imageLine.right==nil){
                        imageLine.right = image
                    }
                    
                    if(imageLine.left != nil && imageLine.right != nil){
                        self.images.append(imageLine)
                        imageLine = ImageLine(left: nil, right: nil)
                    }
                }
                succCallBack()
            case let .failure(error):
                print(error.localizedDescription)
                errorCallBack()
            }
        }
    }
}
