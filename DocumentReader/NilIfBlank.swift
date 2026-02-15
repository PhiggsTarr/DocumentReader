//
//  Optional+NilIfBlank.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 2/14/26.
//

import Foundation

extension Optional where Wrapped == String {
    /// Returns nil if the string is nil, empty, or only whitespace/newlines.
    var nilIfBlank: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }
}


