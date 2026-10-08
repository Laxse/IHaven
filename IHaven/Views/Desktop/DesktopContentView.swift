//
//  DesktopContentView.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/14.
//  Copyright © 2020 梁霄. All rights reserved.
//


import SwiftUI

struct DesktopContentView: View {
    enum Category: String, Hashable, CaseIterable, Identifiable {
        case latest, hot, toplist, random, tags, design, advance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .latest: return "Latest"
            case .hot: return "Hot"
            case .toplist: return "Toplist"
            case .random: return "Random"
            case .tags: return "Tags"
            case .design: return "Design"
            case .advance: return "Advance"
            }
        }

        var icon: String {
            switch self {
            case .latest: return "timer"
            case .hot: return "flame"
            case .toplist: return "rosette"
            case .random: return "arrow.branch"
            case .tags: return "tag"
            case .design: return "wand.and.stars"
            case .advance: return "hammer"
            }
        }
    }

    @State private var selection: Category? = .latest

    private var mainCategories: [Category] { [.latest, .hot, .toplist, .random, .tags, .design] }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(mainCategories) { category in
                        NavigationLink(value: category) {
                            Label(category.title, systemImage: category.icon)
                        }
                        .frame(height: 28)
                    }
                }
                Section {
                    NavigationLink(value: Category.advance) {
                        Label(Category.advance.title, systemImage: Category.advance.icon)
                    }
                    .frame(height: 28)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
        } detail: {
            NavigationStack {
                detailView(for: selection ?? .latest)
            }
        }
    }

    @ViewBuilder
    func detailView(for category: Category) -> some View {
        switch category {
        case .latest: LatestContentView()
        case .hot: HotContentView()
        case .toplist: ToplistContentView()
        case .random: RandomContentView()
        case .tags: TagsContentView()
        case .design: DesignContentView()
        case .advance: AdvanceContentView()
        }
    }
}