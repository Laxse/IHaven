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

final class WallHavenImageRepository: @unchecked Sendable {
    static let shared = WallHavenImageRepository()
    private init() {}

    @discardableResult
    func query(parameters: Parameters?, callback: @escaping @Sendable (Result<QueryResponse, any Error>) -> Void) -> DataRequest {
        AF.request(QueryAPI,
                   method: .get,
                   parameters: parameters,
                   headers: nil
        )
            .responseData { response in
                switch response.result {
                case let .success(data):
                    callback(Self.handle(data))
                case let .failure(error):
                    callback(.failure(error))
                }
        }
    }

    //解析Response 为目标类型
    private static func handle<T: Decodable>(_ response: Data) -> Result<T, any Error> {
        do {
            return .success(try JSONDecoder().decode(T.self, from: response))
        } catch {
            let nsError = NSError(domain: "WallHavenDataError", code: 0, userInfo: [NSLocalizedDescriptionKey : "解析数据异常"])
            return .failure(nsError)
        }
    }

    func downloadImage(url: URL, procressCallback: @escaping @Sendable (Progress) -> Void, callback: @escaping @Sendable () -> Void) {
        let destination = DownloadRequest.suggestedDownloadDestination(for: .downloadsDirectory)
        AF.download(url.description, to: destination)
            .downloadProgress { progress in
                procressCallback(progress)
            }
            .response { _ in
                callback()
            }
    }
}