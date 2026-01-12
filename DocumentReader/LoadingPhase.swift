//
//  LoadingPhase.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/11/26.
//

import Foundation

enum LoadingPhase: String, CaseIterable {
    case scanning = "Scanning"
    case extracting = "Extracting text"
    case analyzing = "Analyzing"
    case interpreting = "Interpreting"
    case researching = "Researching"
    case summarizing = "Summarizing"
    case drafting = "Drafting responses"

    static var rotating: [LoadingPhase] {
        [.analyzing, .interpreting, .researching, .summarizing, .drafting]
    }
}
