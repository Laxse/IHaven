//
//  DImageRepository.swift
//  IHaven
//
//  Created by 梁霄 on 2020/8/18.
//  Copyright © 2020 梁霄. All rights reserved.
//  适用于Desktop版的图片仓库

import Foundation

@MainActor
final class DImageRepository: ObservableObject {
    @Published var images:[WallHavenImage] = []
    @Published var query:QueryParameter = QueryParameter()
    /// 服务端返回的总页数，未加载时为 nil
    @Published var lastPage: Int?
    var loaded = false

    init() {
    }

    init(query: QueryParameter) {
        self.query = query
    }

    func isLoaded() -> Bool {
        loaded
    }

    func clean() {
        images.removeAll()
        lastPage = nil
    }

    func reset() -> Void {
        query.page = 1
        load(succCallBack: {
            //成功
        }, errorCallBack: {
            //失败
        })
    }

    func jump(to: Int, succCallBack: @escaping @Sendable () -> Void, errorCallBack: @escaping @Sendable () -> Void) {
        query.page = to
        load(succCallBack: succCallBack, errorCallBack: errorCallBack)
    }

    func load(succCallBack: @escaping @Sendable () -> Void, errorCallBack: @escaping @Sendable () -> Void) {
        let params = query.toSendableParameters()
        WallHavenImageRepository.shared.query(parameters: params) { result in
            Task { @MainActor in
                switch result {
                case let .success(data):
                    self.images.removeAll()
                    self.images.append(contentsOf: data.data)
                    self.lastPage = data.meta.lastPage
                    self.loaded = true
                    succCallBack()
                case .failure:
                    errorCallBack()
                }
            }
        }
    }
}