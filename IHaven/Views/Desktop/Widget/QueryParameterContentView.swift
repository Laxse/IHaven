//
//  QueryParameterContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2021/9/2.
//  Copyright © 2021 梁霄. All rights reserved.
//

import SwiftUI
struct QueryParameterContentView: View {
    @ObservedObject var imageRepository: DImageRepository
    init(repo:DImageRepository) {
        self.imageRepository = repo
        if(!repo.isLoaded()){
            repo.load {
                print("loaded")
            } errorCallBack: {
                
            }
        }
    }
    
    var body: some View {
        ZStack(content: {
            ScrollView{
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum:240,maximum:240), spacing: 15)
                ], spacing: 15){
                    ForEach(self.imageRepository.images, id: \.self) { platform in
                        ImagePanel(image: platform,imageWidth: 240,imageHeight: 160);
                    }
                }
                .padding(.all, 20)
                .padding(.top, 20)
            }.edgesIgnoringSafeArea(.all)
            HStack(alignment: .center) {
                Spacer()
                Pagination(count: 5000, size: 24, active: self.imageRepository.query.page,changeFunc: { page in
                    self.imageRepository.jump(to: page, succCallBack: {
                        // success
                    }) {
                        // error
                    }
                })
                    .padding(.trailing, 10)
                    .frame(maxHeight: .infinity)
            }.edgesIgnoringSafeArea(.all)
        }).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
}
