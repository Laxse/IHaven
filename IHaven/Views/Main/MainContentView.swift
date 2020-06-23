//
//  MainContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct MainContentView: View {
    @ObservedObject var imageRepository: ImageRepository = ImageRepository()
    var body: some View {
        VStack(spacing: 0){
            MainHeader(imageRepository: imageRepository)
            List() {
                ForEach(imageRepository.images) { imageLine in
                    HStack(spacing: 10){
                        ImagePanel(image: imageLine.left).frame(maxWidth: .infinity)
                        ImagePanel(image: imageLine.right).frame(maxWidth: .infinity)
                    }.onAppear {
                        self.lastImageLineAppear(imageLine: imageLine)
                    }
                }
                HStack{
                    ActivityIndicator(.constant(imageRepository.loading))
                }.frame(maxWidth:.infinity)
            }
            .onAppear {
                self.load()
            }
            MainFooter()
        }.frame(maxHeight: .infinity)
    }
    
}

extension MainContentView{
    private func lastImageLineAppear(imageLine:ImageLine){
        if self.imageRepository.images.isLastItem(imageLine) {
            print("is last now Herry up")
            if(!self.imageRepository.loading){
                load()
            }
        }
    }
    private func load() {
        if(true){
            self.imageRepository.loading = true
            do {
                if let bundlePath = Bundle.main.path(forResource: "data",
                                                     ofType: "json"),
                    let jsonData = try String(contentsOfFile: bundlePath).data(using: .utf8) {
                    let decodedData = try JSONDecoder().decode(QueryResponse.self, from: jsonData)
                    var imageLine = ImageLine(left: nil, right: nil)
                    decodedData.data.forEach { image in
                        if(imageLine.left==nil){
                            imageLine.left = image
                        }else if(imageLine.right==nil){
                            imageLine.right = image
                        }
                        
                        if(imageLine.left != nil && imageLine.right != nil){
                            self.imageRepository.images.append(imageLine)
                            imageLine = ImageLine(left: nil, right: nil)
                        }
                    }
                }
                self.imageRepository.loading = false
            } catch {
                print(error)
            }
            return
        }else{
            self.imageRepository.loading = true
            self.imageRepository.load(succCallBack: {
                //成功
                self.imageRepository.loading = false
            }) {
                //失败
                self.imageRepository.loading = false
            }
        }
    }
}
