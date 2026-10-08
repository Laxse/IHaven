//
//  ImageRepository.swift
//  IHaven
//
//  Created by 2020/6/23.
//  Copyright © 2020 梁霄. All rights reserved.
//

import Foundation

@MainActor
final class ImageRepository: ObservableObject {
    @Published var images:[ImageLine] = []
    @Published var query:QueryParameter = QueryParameter()
    @Published var loading:Bool = false

    static let shared = ImageRepository()
    private init() {
        load()
    }

    func clean() {
        self.images.removeAll()
    }

    func lastImageLineAppear(currentItem:ImageLine) {
        if self.images.isLastItem(currentItem) && !self.loading {
            load()
        }
    }

    private func load() {
        guard !loading else { return }
        load(succCallBack: {
            //成功
        }, errorCallBack: {
            //失败
        })
    }

    func load(succCallBack: @escaping @Sendable () -> Void, errorCallBack: @escaping @Sendable () -> Void) {
        self.loading = true
        let params = query.toSendableParameters()
        WallHavenImageRepository.shared.query(parameters: params) { result in
            Task { @MainActor in
                switch result {
                case let .success(data):
                    self.query.page = self.query.page + 1
                    var imageLines:[ImageLine] = []
                    var imageLine = ImageLine(left: nil, right: nil)
                    data.data.forEach { image in
                        if imageLine.left == nil {
                            imageLine.left = image
                        } else if imageLine.right == nil {
                            imageLine.right = image
                        }
                        if imageLine.left != nil && imageLine.right != nil {
                            imageLines.append(imageLine)
                            imageLine = ImageLine(left: nil, right: nil)
                        }
                    }
                    self.images.append(contentsOf: imageLines)
                    self.loading = false
                    succCallBack()
                case .failure:
                    self.loading = false
                    errorCallBack()
                }
            }
        }
    }
}