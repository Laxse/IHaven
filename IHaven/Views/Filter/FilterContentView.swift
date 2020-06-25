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
            QueryBody().padding(.top,0)
            Spacer()
        }
    }
    
}
struct QueryBody: View {
    var body: some View{
        List(){
            
            Section(header:FilterPartLabel(label: "Category")) {
                HStack {
                    Button(action: {}) {
                        Text("General")
                    }
                    Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/) {
                        Text("Anime")
                    }
                    Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/) {
                        Text("People")
                    }
                }
                
            }
            
            Section(header:FilterPartLabel(label: "Purity")) {
                HStack {
                    Button(action: {}) {
                        Text("SFW")
                    }
                    Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/) {
                        Text("Sketchy")
                    }
                    Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/) {
                        Text("NSFW")
                    }
                }
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

struct FilterContentView_Previews: PreviewProvider {
    @Binding var currentView: ViewState
    static var previews: some View {
        QueryBody()
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
