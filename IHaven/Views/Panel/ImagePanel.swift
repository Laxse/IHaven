//
//  ImagePanel.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/16.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct ImagePanel: View {
    
    let image: WallHavenImage?
    @State private var showHoverDetail = false
    var body: some View {
        ZStack(alignment: .center){
            WebImage(url: image?.thumbs.small)
                .placeholder(Image.init("FilterBtn"))
                .resizable()
                .frame(width:180,height: 120)
                .scaledToFill()
                .border(colorFor(purity: image?.purity ?? "sfw"),width: 2.0)
                .clipped()
                .onHover { state in
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.showHoverDetail = state
                    }
                    
            }.onTapGesture {
                print(self.image?.shortUrl ?? "unknown")
            }
            //            .zIndex(1)
            
            if showHoverDetail && (image != nil) {
                VStack(alignment: .leading) {
                    Text("HelloWorld")
                    Spacer()
                    
                    HStack {
                        ZStack(){
                            HStack{
                                Spacer()
                                Text(resolutionFor(image: image)).foregroundColor(Color.init(red: 255/255, green: 251/255, blue: 240/255,opacity: 0.8))
                                Spacer()
                            }.frame(maxWidth: .infinity)
                            HStack(spacing:0){
                                Text(image?.favorites.description ?? "0")
                                Image("StarBtn").resizable().frame(width: 14, height: 14)
                                Spacer()
                                Text(typeTextFor(image: image)).font(.system(size: 12)).padding(.horizontal, 2).padding(.top, -3).background(Color.init(red: 219/255, green: 124/255, blue: 15/255)).cornerRadius(2)
                                Image("TagBtn").resizable().frame(width: 16, height: 16)
                                
                            }.frame(maxWidth: .infinity)
                        }
                        
                    }.background(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.1)]), startPoint: .bottom, endPoint: .top))
                    
                }.frame(width:176,height: 116)
                //                .zIndex(2)
            }
        }
    }
    
    
    //返回分辨率
    func resolutionFor(image:WallHavenImage?) -> String {
        return image!.resolution
    }
    func typeTextFor(image:WallHavenImage?) -> String {
        if(image!.fileType.hasSuffix("png")){
            return "png"
        }else{
            return ""
        }
    }
    
    //返回purity边框色
    func colorFor(purity:String) -> Color {
        if(purity.caseInsensitiveCompare("sfw") == .orderedSame){
            return Color.clear
        }else if(purity.caseInsensitiveCompare("sketchy") == .orderedSame){
            return Color.init(red: 255/255, green: 200/255, blue: 64/255,opacity: 0.8)
        }else if(purity.caseInsensitiveCompare("nsfw") == .orderedSame){
            return Color.init(red: 255/255, green: 64/255, blue: 48/255,opacity: 0.8)
        }
        return Color.clear
    }
    
    
}
