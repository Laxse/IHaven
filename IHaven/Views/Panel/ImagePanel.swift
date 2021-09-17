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
    // 图片加载状态
    @State var status: ImageState = .None
    // 显示图片详情
    @State var showHoverDetail = false
    // 下载状态
    @State var downloadState: DownloadState = .Nope
    // 下载进度
    @State var downloadProgress: Double = 0.0
    
    @State var imageWidth: CGFloat = 180
    
    @State var imageHeight: CGFloat = 120
    
    @State var clickEvent: (() -> Void)?
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
                .frame(width: imageWidth,height: imageHeight)
                .scaledToFill()
                .border(colorFor(purity: image?.purity ?? "sfw"),width: 2.0)
                .clipped()
                .cornerRadius(2.0)
                .onHover { state in
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.showHoverDetail = state
                    }
            }.onTapGesture {
                // image not well
                if clickEvent == nil{
                    self.downloadImage()
                }else{
                    clickEvent!()
                }
                // self.downloadImage()
                
            }
            
            //图片上层悬浮信息
            if showHoverDetail && (image != nil) {
                VStack(alignment: .leading) {
                    //                    Text(_msg)
                    Spacer()
                    
                    HStack {
                        ZStack(){
                            HStack{
                                Spacer()
                                Text(resolutionFor(image: image)).foregroundColor(Color.init(hex: "FFFBF0"))
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
                                        .background(Color.init(hex: "DB7C0F"))
                                        .cornerRadius(2)
                                }
                                Image("TagBtn").resizable().frame(width: 16, height: 16)
                                
                            }.frame(maxWidth: .infinity).frame(height:20).padding(.horizontal, 3)
                        }
                        
                    }.background(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.1)]), startPoint: .bottom, endPoint: .top))
                    
                }
                .border(colorFor(purity: image?.purity ?? "sfw"),width: 2.0)
                .frame(width: imageWidth,height: imageHeight)
            }
            
            if downloadState == .Doing {
                Color.black.opacity(0.3)
                ProgressBar(progress: $downloadProgress)
            }
            if showHoverDetail && downloadState == .Done {
                //TODO 设置壁纸按钮
                Button(action: {
                    self.setImageAsWallPaper()
                }){
                    VStack(alignment: .center) {
                        Text("Set").font(.body).fontWeight(.ultraLight).foregroundColor(Color.purple)
                        Text("WallPaper").font(.body).fontWeight(.ultraLight).foregroundColor(Color.purple)
                    }.frame(width: 80, height: 80).background(Color.black.opacity(0.7)).cornerRadius(100)
                }.buttonStyle(BorderlessButtonStyle()).padding()
            }
        }
    }
    
    
}

//状态函数
extension ImagePanel{
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
            return Color.init(hex: "FFC840")
        }else if(purity.caseInsensitiveCompare("nsfw") == .orderedSame){
            return Color.init(hex: "FF4030")
        }
        return Color.clear
    }
}

//事件函数
extension ImagePanel{
    // 下载图片点击事件
    func downloadImage() -> Void {
        if(self.status != .Success){
            return
        }
        // check if download
        if(self.checkImageExist()){
            self.downloadState = .Done
        }
        if(self.downloadState == .Nope){
            self.downloadState = .Doing
            WallHavenImageRepository.shared.downloadImage(url: self.image!.path, procressCallback: { progress in
                self.downloadProgress = progress.fractionCompleted
            }, callback: {
                self.downloadState = .Done
            })
        }
    }
    
    // 设置壁纸点击事件
    func setImageAsWallPaper() -> Void {
        do {
            let imgurl = self.getDownloadImagePath()
            let workspace = NSWorkspace.shared
            if let screen = NSScreen.main  {
                try workspace.setDesktopImageURL(imgurl!, for: screen, options: [:])
            }
        } catch {
            print(error)
        }
    }
    
    //校验图片是否存在
    func checkImageExist() -> Bool {
        if let imagePathComponent = getDownloadImagePath() {
            let imagePath = imagePathComponent.path
            if FileManager.default.fileExists(atPath: imagePath) {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    //返回图片名
    func getDownloadImagePath() -> URL? {
        let downloadPath = NSURL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true)[0] as String)
        let imageUrl = image!.path.absoluteString
        return downloadPath.appendingPathComponent(imageUrl[imageUrl.lastIndex(of: "/")!..<imageUrl.endIndex].description as String)
        
    }
}

//进度视图
struct ProgressBar: View {
    
    @Binding var progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 12.0)
                .opacity(0.3)
                .foregroundColor(Color.purple)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 12.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(Color.purple)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear)
            
            Text(String(format: "%.0f %%", min(progress, 1.0)*100.0))
                .font(.headline)
                .fontWeight(.ultraLight)
        }.frame(maxWidth: 80,maxHeight: 80, alignment: .center)
    }
}
