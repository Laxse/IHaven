//
//  WallHavenImageRepository.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/15.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation
import Alamofire


private let QueryAPI = "https://wallhaven.cc/api/v1/search"
private let InfoApi = "https://wallhaven.cc/api/v1/w/"
class WallHavenImageRepository {
    static let shared = WallHavenImageRepository()
    private init() {}
    
    @discardableResult
    func query(parameters:Parameters?,callback:@escaping (Result<QueryResponse,Error>) -> Void) -> DataRequest {
        AF.request(QueryAPI,
                   method: .get,
                   parameters: parameters,
                   headers: []
//            ,requestModifier: {$0.timeoutInterval = 15}
        )
            .responseData { response in
                switch response.result{
                case let .success(data):
                    print(data)
                    let queryResponse:Result<QueryResponse,Error> = self.HandleData(data)
                    callback(queryResponse)
                case let .failure(error): callback(.failure(error))
                }
                
        }
    }
    
    //解析Response 为目标类型
    func HandleData<T:Decodable>(_ reponse:Data) -> Result<T,Error> {

        do {
            let resultData = try JSONDecoder().decode(T.self, from: reponse)
           
        }
        catch {
            print(error)
        }
        guard let resultData = try? JSONDecoder().decode(T.self, from: reponse)else{
            let error = NSError(domain: "WallHavenDataError", code: 0, userInfo: [NSLocalizedDescriptionKey : "解析数据异常"])
            return .failure(error)
        }
       return .success(resultData)
    }
}
