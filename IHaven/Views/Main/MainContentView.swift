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
    @State private var imageSets: [ImageLine] = []
    @State private var query = QueryParameter()
    @State private var loading = false
    var body: some View {
        VStack(spacing: 0){
            MainHeader()
            List() {
                ForEach(imageSets) { imageLine in
                    HStack(spacing: 10){
                        ImagePanel(image: imageLine.left).frame(maxWidth: .infinity)
                        ImagePanel(image: imageLine.right).frame(maxWidth: .infinity)
                    }.onAppear {
                        self.lastImageLineAppear(imageLine: imageLine)
                    }
                }
                HStack{
                    ActivityIndicator(.constant(loading))
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
        if self.imageSets.isLastItem(imageLine) {
            print("is last now Herry up")

            if(!self.loading){
                load()
            }
        }
    }
    private func load() {
        if(true){
            self.loading = true
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
//                self.loading = false
            } catch {
                print(error)
            }
            return
        }
        self.loading = true
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
                        self.imageSets.append(imageLine)
                        imageLine = ImageLine(left: nil, right: nil)
                    }
                }
                self.loading = false
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
}
