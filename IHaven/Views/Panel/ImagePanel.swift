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
    
    @State var image: WallHavenImage?
    @State var status:ImageState = .None
    @State var showHoverDetail = false
    var body: some View {
        ZStack(alignment: .center){
            WebImage(url: image?.thumbs.small)
                .onFailure(perform: { (Error) in
                    DispatchQueue.main.async {
                        self.image = nil
                        self.status = .Error
                        self.showHoverDetail = false
                    }
                    
                })
                .onSuccess(perform: { _ in
                    DispatchQueue.main.async {
                        self.status = .Success
                    }
                    
                })
                .placeholder(placeholderFor(status:status))
                .resizable()
                .frame(width:180,height: 120)
                .scaledToFill()
                .border(colorFor(purity: image?.purity ?? "sfw"),width: 2.0)
                .clipped()
                .cornerRadius(2.0)
                .onHover { state in
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.showHoverDetail = state
                    }
            }.onTapGesture {
                print(self.image?.shortUrl ?? "unknown")
                //下载图片到Download
                WallHavenImageRepository.shared.downloadImage(url: self.image!.path)
            }
            
            //图片上层悬浮信息
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
                                if(typeTextFor(image: image)){
                                    Text("png")
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 2)
                                        .padding(.top, -3)
                                        .background(Color.init(red: 219/255, green: 124/255, blue: 15/255))
                                        .cornerRadius(2)
                                }
                                Image("TagBtn").resizable().frame(width: 16, height: 16)
                                
                            }.frame(maxWidth: .infinity).frame(height:20).padding(.horizontal, 3)
                        }
                        
                    }.background(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.1)]), startPoint: .bottom, endPoint: .top))
                    
                }
                .border(colorFor(purity: image?.purity ?? "sfw"),width: 2.0)
                .frame(width:180,height: 120)
            }
        }
    }
    
    
    //返回分辨率
    func resolutionFor(image:WallHavenImage?) -> String {
        return image!.resolution
    }
    func placeholderFor(status:ImageState) -> Image {
        if(status == .Error){
            return Image.init("ImageErrorIcon")
        }else{
            return Image.init("LoadingIcon")
            
        }
    }
    //显示png标签
    func typeTextFor(image:WallHavenImage?) -> Bool {
        if(image!.fileType.hasSuffix("png")){
            return true
        }else{
            return false
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
