//
//  MainContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/13.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct MainContentView: View {

    @ObservedObject var imageRepository: ImageRepository = ImageRepository.shared
    @ViewBuilder
    var body: some View {
        VStack(spacing: 0){
            MainHeader()
            List() {
                ForEach(imageRepository.images) { imageLine in
                    HStack(spacing: 10){
                        ImagePanel(image: imageLine.left, imageWidth: 175).frame(maxWidth: .infinity)
                        ImagePanel(image: imageLine.right, imageWidth: 175).frame(maxWidth: .infinity)
                    }
                    .onAppear {
                        imageRepository.lastImageLineAppear(currentItem: imageLine)
                    }
                }
                HStack{
                    if imageRepository.loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            MainFooter()
        }
        .frame(maxHeight: .infinity)
    }
}