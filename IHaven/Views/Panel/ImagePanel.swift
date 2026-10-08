//
//  ImagePanel.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/16.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct ImagePanel: View {

    let image: WallHavenImage?
    // 显示图片详情
    @State private var showHoverDetail = false
    // 下载状态
    @State private var downloadState: DownloadState = .Nope
    // 下载进度
    @State private var downloadProgress: Double = 0.0
    // 图片加载失败
    @State private var loadFailed = false

    let imageWidth: CGFloat
    var imageHeight: CGFloat?
    var clickEvent: ((WallHavenImage) -> Void)?

    init(image: WallHavenImage?, imageWidth: CGFloat, imageHeight: CGFloat? = nil, clickEvent: ((WallHavenImage) -> Void)? = nil) {
        self.image = image
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight ?? imageWidth * 2.0 / 3.0
        self.clickEvent = clickEvent
    }

    private var borderColor: Color {
        colorFor(purity: image?.purity ?? "sfw")
    }

    var body: some View {
        ZStack(alignment: .center){
            WebImage(url: image?.thumbs.small)
                .onFailure { _ in
                    loadFailed = true
                    showHoverDetail = false
                }
                .onSuccess { _, _, _ in
                    loadFailed = false
                }
                .resizable()
                .indicator { _, _ in
                    Image(loadFailed ? "ImageErrorIcon" : "LoadingIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .frame(width: imageWidth, height: imageHeight)
                .aspectRatio(contentMode: .fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(borderColor, lineWidth: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .onHover { state in
                    withAnimation(.easeIn(duration: 0.3)) {
                        showHoverDetail = state
                    }
                }
                .onTapGesture {
                    guard let image else { return }
                    if let clickEvent {
                        clickEvent(image)
                    } else {
                        downloadImage()
                    }
                }

            //图片上层悬浮信息
            if showHoverDetail, let image, !loadFailed {
                hoverDetail(for: image)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(borderColor, lineWidth: 2)
                    }
                    .frame(width: imageWidth, height: imageHeight)
            }

            if downloadState == .Doing {
                Color.black.opacity(0.3)
                ProgressBar(progress: $downloadProgress)
            }
            if showHoverDetail && downloadState == .Done {
                Button(action: setImageAsWallPaper) {
                    VStack(alignment: .center) {
                        Text("Set").font(.body).fontWeight(.ultraLight).foregroundColor(Color.purple)
                        Text("WallPaper").font(.body).fontWeight(.ultraLight).foregroundColor(Color.purple)
                    }
                    .frame(width: 80, height: 80)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding()
            }
        }
        .frame(width: imageWidth, height: imageHeight)
    }
}

//悬浮信息层
private extension ImagePanel {
    func hoverDetail(for image: WallHavenImage) -> some View {
        VStack(alignment: .leading) {
            Spacer()
            HStack {
                ZStack {
                    HStack {
                        Spacer()
                        Text(image.resolution).foregroundColor(Color(hex: "FFFBF0"))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 0) {
                        Text(image.favorites.description)
                        Image("StarBtn").resizable().frame(width: 14, height: 14)
                        Spacer()
                        if isPNG(image) {
                            Text("png")
                                .font(.system(size: 12))
                                .padding(.horizontal, 2)
                                .padding(.top, -3)
                                .background(Color(hex: "DB7C0F"))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        Image("TagBtn").resizable().frame(width: 16, height: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .padding(.horizontal, 3)
                }
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.1)]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
    }

    //显示 png 标签
    func isPNG(_ image: WallHavenImage) -> Bool {
        image.fileType.hasSuffix("png")
    }

    //返回 purity 边框色
    func colorFor(purity: String) -> Color {
        switch purity.lowercased() {
        case "sketchy": return Color(hex: "FFC840")
        case "nsfw": return Color(hex: "FF4030")
        default: return Color.clear
        }
    }
}

//事件函数
private extension ImagePanel {
    // 下载图片点击事件
    func downloadImage() -> Void {
        guard let image else { return }
        if checkImageExist(image) {
            downloadState = .Done
            return
        }
        guard downloadState == .Nope else { return }
        downloadState = .Doing
        WallHavenImageRepository.shared.downloadImage(url: image.path, procressCallback: { progress in
            Task { @MainActor in
                downloadProgress = progress.fractionCompleted
            }
        }, callback: {
            Task { @MainActor in
                downloadState = .Done
            }
        })
    }

    // 设置壁纸点击事件
    func setImageAsWallPaper() -> Void {
        guard let image, let imageURL = downloadImagePath(for: image) else { return }
        do {
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: NSScreen.main ?? NSScreen.screens[0], options: [:])
        } catch {
            print("set wallpaper failed: \(error)")
        }
    }

    //校验图片是否存在
    func checkImageExist(_ image: WallHavenImage) -> Bool {
        guard let path = downloadImagePath(for: image)?.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    //返回下载后的图片路径
    func downloadImagePath(for image: WallHavenImage) -> URL? {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        return downloads.appendingPathComponent(image.path.lastPathComponent)
    }
}

//进度视图
struct ProgressBar: View {

    @Binding var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 12.0)
                .opacity(0.3)
                .foregroundColor(Color.purple)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 12.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(Color.purple)
                .rotationEffect(.degrees(270))
                .animation(.linear, value: progress)

            Text(String(format: "%.0f %%", min(progress, 1.0)*100.0))
                .font(.headline)
                .fontWeight(.ultraLight)
        }
        .frame(maxWidth: 80, maxHeight: 80, alignment: .center)
    }
}