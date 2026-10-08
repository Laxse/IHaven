//
//  QueryParameterContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2021/9/2.
//  Copyright © 2021 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct QueryParameterContentView: View {
    @ObservedObject var imageRepository: DImageRepository
    @State var focus: Bool = false
    @State var image: WallHavenImage?
    let message: String
    let themeColor: Color

    init(repo: DImageRepository, message: String, themeColor: Color) {
        self.imageRepository = repo
        self.message = message
        self.themeColor = themeColor
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message)
                        .fontWeight(.ultraLight)
                        .foregroundColor(themeColor)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 10)
                        .padding(.leading, 20)
                        .frame(height: 30, alignment: .leading)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 240), spacing: 15)], spacing: 15) {
                        ForEach(self.imageRepository.images, id: \.self) { wall in
                            ImagePanel(image: wall, imageWidth: 240, imageHeight: 160) { tapped in
                                self.image = tapped
                                self.focus = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .ignoresSafeArea(.all)
            .blur(radius: self.focus ? 3.0 : 0)

            HStack(alignment: .center) {
                Spacer()
                Pagination(
                    totalPages: self.imageRepository.lastPage ?? 0,
                    size: 24,
                    active: Binding(
                        get: { self.imageRepository.query.page },
                        set: { self.imageRepository.query.page = $0 }
                    ),
                    changeFunc: { page in
                        self.imageRepository.jump(to: page, succCallBack: {
                            // success
                        }, errorCallBack: {
                            // error
                        })
                    }
                )
                .padding(.trailing, 10)
                .frame(maxHeight: .infinity)
            }
            .ignoresSafeArea(.all)

            if self.focus, let image {
                detailOverlay(for: image)
                    .ignoresSafeArea(.all)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if !imageRepository.isLoaded() {
                imageRepository.load(succCallBack: {
                    // success
                }, errorCallBack: {
                    // error
                })
            }
        }
    }

    private func detailOverlay(for image: WallHavenImage) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(image.resolution)
                    .font(.title)
                    .fontWeight(.ultraLight)
                    .padding(.vertical, 20)
                    .frame(width: 200, height: 50)

                HStack(spacing: 0) {
                    ForEach(image.colors, id: \.self) { hex in
                        Rectangle().fill(Color(hex: hex))
                            .frame(width: 30, height: 10)
                    }
                }
                .frame(width: 200, height: 30)

                Divider()

                Text("TAGS")
                    .font(.callout)
                    .fontWeight(.ultraLight)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 20)
                    .padding(.leading, 10)
                    .padding(.bottom, 10)

                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Uploader")
                        Text("Category")
                        Text("Purity")
                        Text("Size")
                        Text("Favorites")
                        Text("Views")
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text(image.id)
                        Text(image.category).foregroundColor(Color.green)
                        Text(image.purity)
                        Text(String(image.fileSize))
                        Text(String(image.favorites)).foregroundColor(Color.blue)
                        Text(String(image.views))
                    }
                    Spacer()
                }

                Divider()

                Text("PROPERTIES")
                    .font(.callout)
                    .fontWeight(.ultraLight)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 20)
                    .padding(.leading, 10)
                    .padding(.bottom, 10)

                Spacer()

                Text("All images remain property of their original owners.")
                    .fontWeight(.light)
                    .foregroundColor(Color.gray)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(width: 200)
                    .border(Color.gray)

                Spacer()
            }
            .frame(width: 200)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(Color.black)

            VStack(alignment: .center) {
                HStack {
                    Spacer()
                    Button {
                        self.focus = false
                    } label: {
                        Image(systemName: "xmark.circle")
                            .resizable()
                            .foregroundColor(Color.red)
                            .frame(width: 15, height: 15)
                    }
                    .buttonStyle(.borderless)
                }
                .padding([.top, .trailing], 10)

                Spacer()

                WebImage(url: image.path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipped()

                Spacer()
            }

            Spacer()
        }
        .background(Color.black)
        .opacity(0.9)
    }
}