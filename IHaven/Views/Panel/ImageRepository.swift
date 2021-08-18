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
    
    static let shared = ImageRepository()
    private init() {
        load()
    }
    
    func clean() {
        self.images.removeAll()
    }
    func lastImageLineAppear(currentItem:ImageLine){
          if self.images.isLastItem(currentItem) {
              print("is last now Herry up")
              if(!self.loading){
                  load()
              }
          }
      }
    
    private func load() {
        if(self.loading){
            return
        }
        // Mark TestPoint
        if(false){
            self.loading = true
            do {
                if let bundlePath = Bundle.main.path(forResource: "data",ofType: "json"),
                    let jsonData = try String(contentsOfFile: bundlePath).data(using: .utf8) {
                    let decodedData = try JSONDecoder().decode(QueryResponse.self, from: jsonData)
                    var imageLines:[ImageLine] = []
                    var imageLine = ImageLine(left: nil, right: nil)
                    decodedData.data.forEach { image in
                        if(imageLine.left==nil){
                            imageLine.left = image
                        }else if(imageLine.right==nil){
                            imageLine.right = image
                        }
                        if(imageLine.left != nil && imageLine.right != nil){
                            imageLines.append(imageLine)
                            imageLine = ImageLine(left: nil, right: nil)
                        }
                    }
                    self.images.append(contentsOf: imageLines)
                }
                self.loading = false
            } catch {
                print(error)
            }
            return
        }else{
            self.load(succCallBack: {
                //成功
            }) {
                //失败
            }
        }
    }
    
    func load(succCallBack: @escaping () -> Swift.Void,errorCallBack:  @escaping () -> Swift.Void) {
        self.loading = true
        WallHavenImageRepository.shared.query(parameters: query.toDictionary()) { result in
            switch result{
            case let .success(data):
                self.query.page = self.query.page + 1
                var imageLines:[ImageLine] = []
                var imageLine = ImageLine(left: nil, right: nil)
                data.data.forEach { image in
                    if(imageLine.left==nil){
                        imageLine.left = image
                    }else if(imageLine.right==nil){
                        imageLine.right = image
                    }
                    
                    if(imageLine.left != nil && imageLine.right != nil){
                        imageLines.append(imageLine)
                        imageLine = ImageLine(left: nil, right: nil)
                    }
                }
                self.images.append(contentsOf: imageLines)
                self.loading = false
                succCallBack()
            case let .failure(error):
                print(error.localizedDescription)
                self.loading = false
                errorCallBack()
            }
        }
    }
}
