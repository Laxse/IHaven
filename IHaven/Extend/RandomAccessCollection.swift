//
//  RandomAccessCollection.swift
//  IHaven
//
//  Created by 梁霄 on 2020/6/21.
//  Copyright © 2020 梁霄. All rights reserved.
//

extension RandomAccessCollection where Self.Element: Identifiable {
    func isLastItem<Item: Identifiable>(_ item: Item) -> Bool {
        guard !isEmpty else {
            return false
        }
        
        guard let itemIndex = firstIndex(where: { $0.id.hashValue == item.id.hashValue }) else {
            return false
        }
        
        let distance = self.distance(from: itemIndex, to: endIndex)
        return distance == 1
    }
}
