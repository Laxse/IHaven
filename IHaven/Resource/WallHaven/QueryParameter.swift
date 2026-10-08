//
//  QueryParameter.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/21.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
final class QueryParameter: @unchecked Sendable {
    static let UNSET = "UNSET"
    static let NULL = "NULL"
    let q:String = ""
    
    /** 100/101/111/etc.. (general/anime/people) */
    var categories:String = "011"
    
    /** 100* /110/111/etc (sfw/sketchy/nsfw)  */
    var purity:String = "100"
    
    static let sortingArray = [UNSET,"date_added","relevance","random","views","favorites","toplist","toplist_random"]
    /** date_added* , relevance, random, views, favorites, toplist, toplist_random */
    var sorting:String = "date_added"
    
    /** desc asc */
    let order:String = "desc"
    
    /** 1d, 3d, 1w,1M*, 3M, 6M, 1y */
    let topPange:String = "1M"
    
    /** 1920x1080 */
    let atleast:String = ""
    
    static let resolutionArray = [UNSET,"1280x720","1280x800","1280x960","1280x1024","1600x900","1600x1000",
                                  "1600x1200","1600x1280","1920x1080","1920x1200","1920x1440","1920x1536",
                                  "2560x1080", "2560x1440","2560x1600","2560x1920","2560x2048","3440x1440",
                                  "3840x1600","3840x2160","3840x2400","3840x2880","3840x3072"]
    
    
    /** 1920x1080,1920x1200 */
    var resolutions:String = ""
    
    static let ratioArray = [UNSET,"9x16","10x16","9x18",    "1x1","3x2","4x3","5x4",    "16x9","16x10",    "21x9","32x9","48x9"]
    /** 16x9,16x10 */
    var ratios:String = ""
    
    /** 660000..... */
    var color:String = "NULL"
    
    /**  */
    var page:Int = 1
    
    /**  */
    var seed:String = ""
    
    let apikey = "CmQyjMpXsdgTlyoME98eaf64cbJCRzac"

    init() {
        
    }
    init(sorting:String) {
        self.sorting = sorting
    }
    func _isUnset(param:String) -> Bool {
        if(param == QueryParameter.UNSET || param == QueryParameter.NULL  || param == ""){
            return true
        }
        return false
    }
    
    func toDictionary() -> [String: Any] {
        toSendableParameters()
    }

    /// 生成可跨并发边界传递的查询参数
    func toSendableParameters() -> [String: Sendable] {
        var result:[String:Sendable] = [:]
        result["q"] = q;
        result["categories"] = categories;
        result["purity"] = purity;
        if(!_isUnset(param: sorting)){
            result["sorting"] = sorting;
            result["order"] = order;
        }
        if(!_isUnset(param: atleast)){
            result["atleast"] = atleast;
        }
        if(!_isUnset(param: resolutions)){
            result["resolutions"] = resolutions;
        }
        if(!_isUnset(param: ratios)){
            result["ratios"] = ratios;
        }
        if(!_isUnset(param: color)){
            result["color"] = color;
        }
        if(!_isUnset(param: topPange)){
            result["topRange"] = topPange;
        }
        result["page"] = page;
        if(seed != ""){
            result["seed"] = seed;
        }
        result["apikey"] = apikey;
        return result
    }
    
    func setCategory(i:Int,v:Bool){
        self.categories.replaceSubrange(
            self.categories.index(self.categories.startIndex, offsetBy: i)...self.categories.index(self.categories.startIndex, offsetBy: i), with: v ? "1" : "0")
    }
    func getCategory(i:Int) -> Bool {
        self.categories[self.categories.index(self.categories.startIndex, offsetBy: i)] == "1"
    }
    func setPurity(i:Int,v:Bool){
        self.purity.replaceSubrange(
            self.purity.index(self.purity.startIndex, offsetBy: i)...self.purity.index(self.purity.startIndex, offsetBy: i), with: v ? "1" : "0")
    }
    func getPurity(i:Int) -> Bool {
        self.purity[self.purity.index(self.purity.startIndex, offsetBy: i)] == "1"
    }
    func setColor(color:String) {
        self.color = color
    }
    func getSortIndex() -> Double {
        if let index = QueryParameter.sortingArray.firstIndex(of: self.sorting) {
            return Double(index)
        }else{
            return Double(0)
        }
        
    }
    func setSorting(v:Int) {
        self.sorting = QueryParameter.sortingArray[v]
    }
    func getResolutionIndex() -> Double {
        if let index = QueryParameter.resolutionArray.firstIndex(of: self.resolutions) {
            return Double(index)
        }else{
            return Double(0)
        }
    }
    func setResolution(v:Int) {
        self.resolutions = QueryParameter.resolutionArray[v]
    }
    
    func getRatioIndex() -> Double {
        if let index = QueryParameter.ratioArray.firstIndex(of: self.ratios) {
            return Double(index)
        }else{
            return Double(0)
        }
    }
    func setRatio(v:Int) {
        self.ratios = QueryParameter.ratioArray[v]
    }
    func random() {
        self.seed = getRandomStringWithNum(num: 6)
    }
    
    private func getRandomStringWithNum(num:Int) -> String {
        var string = ""
        var i = 0
        while i<num {
            i+=1
            let number = arc4random() % 36
            if number < 10{
                let figure = arc4random() % 10;
                let tempString = String(figure)
                string = string + tempString
            } else {
                let figure = (arc4random() % 26) + 97;
                let character = Character(UnicodeScalar(figure)!)
                let tempString = String(character)
                string = string + tempString
            }
        }
        return string
    }
}
