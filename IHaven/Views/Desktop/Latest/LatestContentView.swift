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
                GeometryReader { geometry in
                              self.generateContent(in: geometry)
                          }
            }
          
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
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
                
            ForEach(self.imageRepository.images, id: \.self) { platform in
                self.item(for: platform)
                    .padding([.horizontal, .vertical], 10)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > g.size.width)
                        {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if platform == self.imageRepository.images.last! {
                            width = 0 //last item
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: {d in
                        let result = height
                        if platform == self.imageRepository.images.last! {
                            height = 0 // last item
                        }
                        return result
                    })
            }
        }
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
