//
//  Extensions.swift
//  Nugget
//
//  Created by lemin on 9/9/24.
//

import Foundation
import SwiftUI

extension URL {
    static var documents: URL {
        return FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

/// The reference's `IOSSearchEdit.matches` (`gui/ios/components.py:227`): every
/// whitespace-separated word of the query must appear in the joined haystack,
/// case- and diacritic-insensitively.  An empty (or whitespace-only) query
/// matches everything, which is what makes the field optional.
///
/// Shared by the Tweaks and Daemons pages; the desktop gives both the same
/// search widget, so the two lists cannot disagree about what a query means.
func searchMatches(query: String, _ texts: String...) -> Bool {
    let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !words.isEmpty else { return true }
    let haystack = texts.joined(separator: " ")
    return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
}

// MARK: - Themed list helper
//
// A single line to give a `List`-based page the new background + accent without
// converting it to cards. Used by `FilesView` (kept as a `List` because swipe
// to delete and the context menu are the browser's usability) and by
// `PartialExportSheet` (kept as a `List` for the same reason: a multi-select
// sheet reads better as rows than as a grid of cards).

extension View {
    func appThemedList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(AppPalette.accent)
    }
}