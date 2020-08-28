//
//  DImageRepository.swift
//  IHaven
//
//  Created by 梁霄 on 2020/8/18.
//  Copyright © 2020 梁霄. All rights reserved.
// 适用于Desktop版的图片仓库

import Foundation
class DImageRepository: ObservableObject {
    @Published var images:[WallHavenImage] = []
    @Published var query:QueryParameter = QueryParameter()

    func clean() {
        self.images.removeAll()
    }
    func reset() -> Void {
        query.page = 1;
        load()
    }
    private func load() {
        self.load(succCallBack: {
            //成功
        }) {
            //失败
        }
    }
    
    func load(succCallBack: @escaping () -> Swift.Void,errorCallBack:  @escaping () -> Swift.Void) {
        WallHavenImageRepository.shared.query(parameters: query.toDictionary()) { result in
            switch result{
            case let .success(data):
                self.images.append(contentsOf: data.data)
                succCallBack()
            case let .failure(error):
                print(error.localizedDescription)
                errorCallBack()
            }
        }
    }
}
