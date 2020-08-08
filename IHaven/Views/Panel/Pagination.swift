//
//  Pagination.swift
//  IHaven
//
//  Created by 梁霄 on 2020/8/5.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct Pagination: View {
    @State var count:Int
    @State var size: Int
    @State var active: Int
    var body: some View {
        VStack(alignment: .trailing) {
            Text("Last").font(Font.system(size: 18))
                .fontWeight(.ultraLight)
                .padding()
                .onTapGesture {
                    self.move(distance: -1)
            }
            Text("#"+String(active)).font(Font.system(size: 28))
                .font(.title)
                .fontWeight(.ultraLight)
                .foregroundColor(Color.purple)
                .multilineTextAlignment(.trailing)
                .padding(.all)
            Spacer()
            Text("Next")
                .font(Font.system(size: 18))
                .fontWeight(.ultraLight)
                .padding()
                .onTapGesture {
                    self.move(distance: 1)
            }
            
        }
        
        
    }
}
extension Pagination {
    
    func move(distance:Int) -> Void {
        move(to: self.active + distance)
    }
    
    func move(to: Int) -> Void {
        if(count <= 0){
            return
        }
        
        if(to > 0 && to < Int(ceil(Double(count)/Double(size)))){
            self.active = to
        }
    }
    
}

struct Pagination_Previews: PreviewProvider {
    static var previews: some View {
        Pagination(count: 500, size: 25, active: 5)
    }
}
