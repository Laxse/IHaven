//
//  Pagination.swift
//  IHaven
//
//  Created by 梁霄 on 2020/8/5.
//  Copyright © 2020 梁霄. All rights reserved.
//

import SwiftUI

struct Pagination: View {
    /// 总页数，由服务端 meta.last_page 提供
    let totalPages: Int
    let size: Int
    @Binding var active: Int
    var changeFunc:(Int) -> Swift.Void

    init(totalPages: Int, size: Int, active: Binding<Int>, changeFunc: @escaping (Int) -> Swift.Void) {
        self.totalPages = totalPages
        self.size = size
        self._active = active
        self.changeFunc = changeFunc
    }

    var body: some View {
        VStack(alignment: .trailing) {
            Text("Last")
                .font(.system(size: 18))
                .fontWeight(.ultraLight)
                .foregroundColor(canGoBack ? Color.purple : Color.gray)
                .padding()
                .onTapGesture {
                    move(distance: -1)
                }
            Text("#" + String(active))
                .font(.title)
                .fontWeight(.ultraLight)
                .foregroundColor(Color.purple)
                .multilineTextAlignment(.trailing)
                .padding()

            Spacer()
            Text("Next")
                .font(.system(size: 18))
                .fontWeight(.ultraLight)
                .foregroundColor(canGoForward ? Color.purple : Color.gray)
                .padding()
                .onTapGesture {
                    move(distance: 1)
                }
        }
    }

    private var canGoBack: Bool { totalPages > 0 && active > 1 }
    private var canGoForward: Bool { totalPages > 0 && active < totalPages }
}

private extension Pagination {
    func move(distance:Int) -> Void {
        move(to: active + distance)
    }

    func move(to: Int) -> Void {
        guard totalPages > 0 else { return }
        guard to > 0 && to <= totalPages else { return }
        active = to
        changeFunc(active)
    }
}