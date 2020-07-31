//
//  DownloadState.swift
//  IHaven
//
//  Created by 梁霄 on 2020/7/31.
//  Copyright © 2020 梁霄. All rights reserved.
//

// 下载状态 不包括失败
enum DownloadState {
    case Nope     // 未下载
    case Doing    // 下载中
    case Done     // 下载完成
}
