//
//  FilterContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct FilterContentView: View {
    @ObservedObject var imageRepository: ImageRepository = ImageRepository.shared
    var body: some View {
        VStack(){
            FilterHeader()
            QueryFilter().padding(.top,0)
            Spacer()
        }
    }
    
}
struct QueryFilter: View {
    var body: some View{
        List(){
            Section(header:FilterPartLabel(label: "Category")) {
                Group{
                    HStack(alignment: .bottom, spacing: 5) {
                        CheckableButton(lable: "General", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.white, unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 119/255), clickCallBack: {boolean in
                            print(boolean)
                        }, checked: false)
                        CheckableButton(lable: "Anime", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.white, unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 119/255), clickCallBack: {boolean in
                            print(boolean)
                        }, checked: false)
                        CheckableButton(lable: "People", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.white, unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 119/255), clickCallBack: {boolean in
                            print(boolean)
                        }, checked: false)
                    }.padding(.horizontal, 5).padding(.vertical, 5).background(Color.black)
                }.padding(.top, 10)
                
                
            }
            
            Section(header:FilterPartLabel(label: "Purity")) {
                Group{
                    HStack(alignment: .bottom, spacing: 5) {
                        CheckableButton(lable: "SFW", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.init(red: 153/255, green: 255/255, blue: 153/255), unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 68/255, green: 119/255, blue: 68/255), clickCallBack: {boolean in
                            print(boolean)
                        }, checked: false)
                        CheckableButton(lable: "Sketchy", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.init(red: 255/255, green: 255/255, blue: 153/255), unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 68/255), clickCallBack: {boolean in
                            print(boolean)
                        }, checked: false)
                        CheckableButton(lable: "NSFW", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.init(red: 255/255, green: 153/255, blue: 153/255), unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 68/255, blue: 68/255), clickCallBack: {boolean in
                            print(boolean)
                        }, checked: false)
                    }.padding(.horizontal, 5).padding(.vertical, 5).background(Color.black)
                }.padding(.top, 10)
                
            }
            
            Section(header:FilterPartLabel(label: "Resolution")) {
                Text("Resolution")
            }
            
            Section(header:FilterPartLabel(label: "Ratio")) {
                Text("Ratio")
            }
            
            Section(header:FilterPartLabel(label: "Color")) {
                Text("Color")
            }
            
            Section(header:FilterPartLabel(label: "Sort")) {
                Text("Color")
            }
        }.listStyle(SidebarListStyle())
        
        //        CarouselListStyle
        //        DefaultListStyle
        //        GroupedListStyle
        //        PlainListStyle
        //        SidebarListStyle
        
    }
}


struct FilterPartLabel: View {
    private var label:String
    
    init(label:String) {
        self.label = label
    }
    
    var body: some View{
        Text(label).font(.headline).fontWeight(.ultraLight).foregroundColor(Color.purple).multilineTextAlignment(.leading).shadow(color: .black, radius: 2, x: 0.1, y: 0.1)
            .edgesIgnoringSafeArea(.all)
    }
}


