//
//  MainContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct MainContentView: View {
    @State private var imageSets: [ImageLine] = []
    @State private var page = 1
    var body: some View {
        VStack(spacing: 0){
            MainHeader()
            List(imageSets) { imageLine in
                HStack(spacing: 10){
                    ImagePanel(image: imageLine.left).frame(maxWidth: .infinity)
                    ImagePanel(image: imageLine.right).frame(maxWidth: .infinity)
                }.onAppear {
                    self.lastImageLineAppear(imageLine: imageLine)
                }
            }
            .onAppear {
                self.loadImages()
            }
            MainFooter()
        }.frame(maxHeight: .infinity)
    }
    
}


extension MainContentView{
    private func lastImageLineAppear(imageLine:ImageLine){
        if self.imageSets.isLastItem(imageLine) {
            print("is last now Herry up")
            loadImages()
        }
    }
    private func loadImages() {
        if(true){
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
                            self.imageSets.append(imageLine)
                            imageLine = ImageLine(left: nil, right: nil)
                        }
                    }
                }
            } catch {
                print(error)
            }
            return
        }
        //          WallHavenImageRepository.shared.query(parameters: ["page":self.page,"apikey":"vp1ZWXq92VMfjgBIGejfUgHQCXnw88HF"]) { result in
        //              switch result{
        //              case let .success(data):
        //                  self.page = self.page+1
        //                  self.imageSets.append(contentsOf: data.data)
        //              case let .failure(error):
        //                  print(error.localizedDescription)
        //              }
        //          }
    }
}
