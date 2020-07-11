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
    @ViewBuilder
    var body: some View {
        VStack(){
            FilterHeader()
            QueryFilter(query: imageRepository.query).padding(.top,0)
            Spacer()
        }
    }
    
}
struct QueryFilter: View {
    @State var query:QueryParameter
    var body: some View{
        List(){
            CategorySection(query: $query)
            
            PuritySection(query: $query)
            
            ResolutionSelection(query: $query, select: query.getResolutionIndex(), label: query.resolutions)
            
            RatioSelection(query: $query, select: query.getRatioIndex(), label: query.ratios)
            
            ColorSection(query: $query, currentLabel: query.color)
            
            SortSelection(query: $query, select: query.getSortIndex(), label: query.sorting)
        }.listStyle(SidebarListStyle())
        
    }
}
struct SortSelection:View {
    @Binding var query:QueryParameter
    @State var select: Double
    @State var label:String
    var body: some View{
        Section(header:FilterPartLabel(label: "Sort")) {
            Text(label)
            Slider(value: Binding(get: {
                self.select
            }, set: { value in
                self.select = value
                self.label = QueryParameter.sortingArray[Int(value)]
                self.query.setSorting(v: Int(value))
            }), in: 0...Double(QueryParameter.sortingArray.count-1),step: 1)
        }
    }
}

struct RatioSelection:View {
    @Binding var query:QueryParameter
    @State var select: Double
    @State var label:String
    var body: some View{
        Section(header:FilterPartLabel(label: "Ratio")) {
            Text(label)
            Slider(value: Binding(get: {
                self.select
            }, set: { value in
                self.select = value
                self.label = QueryParameter.ratioArray[Int(value)]
                self.query.setRatio(v: Int(value))
            }), in: 0...Double(QueryParameter.ratioArray.count-1),step: 1)
        }
    }
}

struct ResolutionSelection:View {
    @Binding var query:QueryParameter
    @State var select: Double
    @State var label:String

     var body: some View{
        Section(header:FilterPartLabel(label: "Resolution")) {
            Text(label)
            Slider(value: Binding(get: {
                self.select
            }, set: { value in
                self.select = value
                self.label = QueryParameter.resolutionArray[Int(value)]
                self.query.setResolution(v: Int(value))
            }), in: 0...Double(QueryParameter.resolutionArray.count-1),step: 1)
        }
    }
    
}
//分类条件
struct CategorySection: View {
    @Binding var query:QueryParameter
    var body: some View{
        Section(header:FilterPartLabel(label: "Category")) {
            Group{
                HStack(alignment: .bottom, spacing: 5) {
                    CheckableButton(lable: "General", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.white, unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 119/255), clickCallBack: {boolean in
                        self.query.setCategory(i: 0, v: boolean)
                    }, checked: query.getCategory(i: 0))
                    CheckableButton(lable: "Anime", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.white, unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 119/255), clickCallBack: {boolean in
                        self.query.setCategory(i: 1, v: boolean)
                    }, checked: query.getCategory(i: 1))
                    CheckableButton(lable: "People", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.white, unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 119/255), clickCallBack: {boolean in
                        self.query.setCategory(i: 2, v: boolean)
                    }, checked: query.getCategory(i: 2))
                }.padding(.horizontal, 5).padding(.vertical, 5).background(Color.black)
            }.padding(.top, 10)
        }
    }
}

//图片污力条件
struct PuritySection:View {
    @Binding var query:QueryParameter
    var body: some View{
        Section(header:FilterPartLabel(label: "Purity")) {
            Group{
                HStack(alignment: .bottom, spacing: 5) {
                    CheckableButton(lable: "SFW", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.init(red: 153/255, green: 255/255, blue: 153/255), unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 68/255, green: 119/255, blue: 68/255), clickCallBack: {boolean in
                        self.query.setPurity(i: 0, v: boolean)
                    }, checked: self.query.getPurity(i: 0))
                    CheckableButton(lable: "Sketchy", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.init(red: 255/255, green: 255/255, blue: 153/255), unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 119/255, blue: 68/255), clickCallBack: {boolean in
                        self.query.setPurity(i: 1, v: boolean)
                    }, checked: self.query.getPurity(i: 1))
                    CheckableButton(lable: "NSFW", unclickFontColor: Color.init(red: 170/255, green: 170/255, blue: 170/255), clickFontColor: Color.init(red: 255/255, green: 153/255, blue: 153/255), unclickBackColor: Color.init(red: 94/255, green: 94/255, blue: 94/255), clickBackColor: Color.init(red: 119/255, green: 68/255, blue: 68/255), clickCallBack: {boolean in
                        self.query.setPurity(i: 2, v: boolean)
                    }, checked: self.query.getPurity(i: 2))
                }.padding(.horizontal, 5).padding(.vertical, 5).background(Color.black)
            }.padding(.top, 10)
            
        }
    }
}


struct ColorSection:View {
    @Binding var query:QueryParameter
    @State var currentLabel:String
    var body: some View{
        Section(header:FilterPartLabel(label: "Color")) {
            VStack(alignment: .leading, spacing: 5, content: {
                HStack{
                    Text(currentLabel)
                    Spacer()
                }
                //TODO 改成等宽字体
                HStack(spacing: 5){
                    ColorText(currentLabel: $currentLabel, query: $query ,label: "660000")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "990000")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "CC0000")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "CC3333")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "EA4C88")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "993399")
                }
                HStack(spacing: 5){
                    ColorText(currentLabel: $currentLabel, query: $query, label: "663399")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "333399")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "0066CC")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "0099CC")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "66CCCC")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "77CC33")
                }
                HStack(spacing: 5){
                    ColorText(currentLabel: $currentLabel, query: $query, label: "669900")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "336600")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "666600")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "999900")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "CCCC33")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "FFFF00")
                }
                HStack(spacing: 5){
                    ColorText(currentLabel: $currentLabel, query: $query,label: "FFCC33")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "FF9900")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "FF6600")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "CC6633")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "996633")
                    ColorText(currentLabel: $currentLabel, query: $query,label: "663300")
                }
                HStack(spacing: 5){
                    ColorText(currentLabel: $currentLabel, query: $query, label: "000000")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "999999")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "CCCCCC")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "FFFFFF")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "424153")
                    ColorText(currentLabel: $currentLabel, query: $query, label: "NULL")
                }
            })
        }
    }
}



//section 标题
struct FilterPartLabel: View {
    var label:String
    
    var body: some View{
        Text(label).font(.headline).fontWeight(.ultraLight).foregroundColor(Color.purple).multilineTextAlignment(.leading).shadow(color: .black, radius: 2, x: 0.1, y: 0.1)
            .edgesIgnoringSafeArea(.all)
    }
}

//颜色过滤配置
struct ColorText:View {
    @Binding var currentLabel:String
    @Binding var query:QueryParameter
    var label:String
    var body: some View{
        Text(label).font(.system(size: 8)).frame(width: 40, height: 20, alignment: .bottomTrailing).padding(.all, 5).background(Color.init(hex: label)).onTapGesture {
            self.query.setColor(color: self.label)
            self.currentLabel = self.label
        }
    }
}

