//
//  QueryParameter.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/21.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
class QueryParameter {
    
    let q:String = ""
    
    /** 100/101/111/etc.. (general/anime/people) */
    let categories:String = "011"
    
    /** 100* /110/111/etc (sfw/sketchy/nsfw)  */
    let purity:String = "100"
    
    /** date_added* , relevance, random, views, favorites, toplist */
    let sorting:String = "date_added"
    
    /** desc asc */
    let order:String = "desc"
    
    /** 1d, 3d, 1w,1M*, 3M, 6M, 1y */
    let topPange:String = "1M"
    
    /** 1920x1080 */
    let atleast:String = ""
    
    /** 1920x1080,1920x1200 */
    let resolutions:String = ""
    
    /** 16x9,16x10 */
    let ratios:String = ""
    
    /** 660000..... */
    let color:String = ""
    
    /**  */
    var page:Int = 1
    
    /**  */
    let seed:String = ""
    
    let apikey = "vp1ZWXq92VMfjgBIGejfUgHQCXnw88HF"
    
    func toDictionary() -> [String: Any] {
        var  result:[String:Any] =  [:]
        result["q"] = q;
        result["categories"] = categories;
        result["purity"] = purity;
        result["sorting"] = sorting;
        result["order"] = order;
        result["topPange"] = topPange;
        result["atleast"] = atleast;
        result["resolutions"] = resolutions;
        result["ratios"] = ratios;
        result["color"] = color;
        result["page"] = page;
        result["seed"] = seed;
        result["apikey"] = apikey;
        return result
    }
    
}
