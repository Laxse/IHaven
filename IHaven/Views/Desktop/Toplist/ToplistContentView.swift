//
//  ToplistContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct ToplistContentView: View {
    @ObservedObject var imageRepository: DImageRepository = DImageRepository(query: QueryParameter(sorting: "toplist"))
    
    init() {
        imageRepository.load(succCallBack: {
            print("Toplist loaded")
        }) {
            
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
