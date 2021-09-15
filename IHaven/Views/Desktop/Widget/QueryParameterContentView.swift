//
//  QueryParameterContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2021/9/2.
//  Copyright © 2021 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI
struct QueryParameterContentView: View {
    @ObservedObject var imageRepository: DImageRepository
    var message: String
    var themeColor: Color
    init(repo:DImageRepository,message:String,themeColor:Color) {
        self.imageRepository = repo
        self.message = message
        self.themeColor = themeColor
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
                HStack{
                    Text(message)
                        .fontWeight(.ultraLight)
                        .foregroundColor(themeColor)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 10)
                        .padding(.leading, 20)
                    Spacer()
                }.frame(minHeight: 30, idealHeight: 30, maxHeight: 30)
                
                    
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum:240,maximum:240), spacing: 15)
                ], spacing: 15){
                    ForEach(self.imageRepository.images, id: \.self) { platform in
                        ImagePanel(image: platform,imageWidth: 240,imageHeight: 160);
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, 20)
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
           
            HStack(alignment: .center, content: {
                Spacer()
                VStack(alignment: .center, content: {
                    Spacer()
//                    WebImage(url:URL(string: "https://w.wallhaven.cc/full/g7/wallhaven-g75r7d.jpg") )
//                        .resizable()
//                        .scaledToFill()
//                        .clipped()
//                        .cornerRadius(2.0)
                    Label(
                        title: { Text("Label") },
                        icon: { Image(systemName: "42.circle") })
                    Spacer()
                })
                Spacer()
            })
            .background(Color.red)
            .padding(.horizontal, 50)
            .padding(.vertical, 100)
            .edgesIgnoringSafeArea(.all)
        }).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
}



struct SwiftUIView_Previews: PreviewProvider {
    
    static var previews: some View {
        QueryParameterContentView(repo:DImageRepository(),message: "The latest wallpapers uploaded by our awesome community!",themeColor: Color.green)

    }
}
