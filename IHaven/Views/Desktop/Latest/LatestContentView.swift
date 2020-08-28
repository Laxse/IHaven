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
                HStack(alignment: .center) {
                    Spacer()
                    Pagination(count: 5000, size: 24, active: 1)
                        .padding(.trailing, 10)
                        .frame(maxHeight: .infinity)
                }
                ScrollView{
                    VStack(alignment: .center, spacing: 10) {
                                        ForEach(imageRepository.images) { image in
                                           WebImage(url: image.thumbs.small)
                                             .onFailure(perform: { (Error) in
                                                
                                             })
                                             .onSuccess(perform: { _ in
                                              
                                             })
                                             .resizable()
                                             .frame(width:180,height: 120)
                                             .scaledToFill()
                                             .clipped()
                                             .cornerRadius(2.0)
                                       }
                                       
                                       Spacer()
                                   }.background(Color.yellow)
                }
               
            }).frame(maxWidth: .infinity, maxHeight: .infinity) .edgesIgnoringSafeArea(.all)
    }
}

struct LatestContentView_Previews: PreviewProvider {
    static var previews: some View {
        LatestContentView()
    }
}
