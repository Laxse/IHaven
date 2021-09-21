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
    @State var focus: Bool = false
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
                        ImagePanel(image: platform,imageWidth: 240,imageHeight: 160) {
                            focus = true
                        };
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, 20)
            }.edgesIgnoringSafeArea(.all)
            .blur(radius: blurForBackground(focus: self.focus) )
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
            if focus == true {
                HStack(alignment: .center, content: {
                    VStack(alignment: .leading, spacing: 0,content: {
                        Text("1920 x 1080")
                            .font(.title)
                            .fontWeight(.ultraLight)
                            .padding(.vertical, 20.0)
                            .frame(width: 200, height: 50, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        HStack(alignment: .center, spacing: 0.0, content: {
                            Rectangle().fill(Color.red)
                                .frame(width: 30, height: 10, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                            Rectangle().fill(Color.blue)
                                .frame(width: 30, height: 10, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                            Rectangle().fill(Color.gray)
                                .frame(width: 30, height: 10, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                            Rectangle().fill(Color.pink)
                                .frame(width: 30, height: 10, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                            Rectangle().fill(Color.purple)
                                .frame(width: 30, height: 10, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        }).frame(width: 200, height: 50, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        Divider()
                        Text("TAGS")
                            .font(.callout)
                            .fontWeight(.ultraLight)
                            .multilineTextAlignment(.leading)
                            .padding(.top,20)
                            .padding(.leading, /*@START_MENU_TOKEN@*/10/*@END_MENU_TOKEN@*/)
                            .padding(.bottom,10)
                        HStack(content: {
                            Text("Uploader")
                            Text("Uploader")
                        })
                        Divider()
                        Text("PROPERTIES")
                            .font(.callout)
                            .fontWeight(.ultraLight)
                            .multilineTextAlignment(.leading)
                            .padding(.top,20)
                            .padding(.leading, /*@START_MENU_TOKEN@*/10/*@END_MENU_TOKEN@*/)
                            .padding(.bottom,10)
                        
                        
                        Spacer()
                        Text("All images remain property of their original owners.")
                            .fontWeight(.light)
                            .foregroundColor(Color.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(width: 200)
                            .border(Color.gray)
                        Spacer()
                        // tags
                        // user info
                    })
                    .frame(minWidth: 200,idealWidth: 200,maxWidth: 200,maxHeight: .infinity, alignment: .center)
                    .background(Color.black)
                    VStack(alignment: .center, content: {
                        Spacer()
                        Label(
                            title: { Text("Label") },
                            icon: { Image(systemName: "42.circle") }).onTapGesture {
                                self.focus = false
                            }
                        Spacer()
                    })
                    Spacer()
                })
                .background(Color.black)
                .opacity(0.9)
                
                
                .edgesIgnoringSafeArea(.all)
            }
           
        }).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func blurForBackground(focus: Bool) -> CGFloat {
        if focus {
            return 3.0
        }else{
            return 0
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
}



struct SwiftUIView_Previews: PreviewProvider {
    
    static var previews: some View {
        QueryParameterContentView(repo:DImageRepository(),message: "The latest wallpapers uploaded by our awesome community!",themeColor: Color.green)

    }
}
