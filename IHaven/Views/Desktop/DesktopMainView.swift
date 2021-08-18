//
//  DesktopMain.swift
//  IHaven
//
//  Created by 梁霄 on 2020/11/14.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct DesktopMainView: View {
    @State var search = ""
       var body: some View{
           SearchBar(search: self.$search)
               .padding()
           VStack{
               Spacer()
               Text("搜索:\(self.search)")
               Spacer()
           }
           Spacer()
       }
}

struct DesktopMain_Previews: PreviewProvider {
    static var previews: some View {
        DesktopMainView()
    }
}

struct SearchBar:View{
    @Binding var search:String
    var body: some View{
        HStack(spacing: 12){
            HStack(spacing: 15){
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)

                TextField("Search", text: $search)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.vertical,10)
            .padding(.horizontal)
            .background(Color.white)
            .cornerRadius(10)

            Button(action: {}, label: {
                Image(systemName: "line.horizontal.3.decrease.circle")
                    .foregroundColor(.black)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 5, y: 5)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: -5, y: -5)
            })
            .buttonStyle(PlainButtonStyle())
        }
    }
}
