//
//  LatestContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/22.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct LatestContentView: View {
    @ObservedObject var imageRepository: DImageRepository = DImageRepository()
    
    init() {
        imageRepository.load(succCallBack: {
            
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
                        self.item(for: platform)
                            
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
    
  
    func item(for image: WallHavenImage) -> some View {
        WebImage(url: image.thumbs.small)
            .onFailure(perform: { (Error) in
                
            })
            .onSuccess(perform: { _ in
                
            })
            .resizable()
            .frame(width:240,height: 160)
            .scaledToFill()
            .clipped()
            .cornerRadius(2.0)
    }
}

struct LatestContentView_Previews: PreviewProvider {
    static var previews: some View {
        LatestContentView()
    }
}


