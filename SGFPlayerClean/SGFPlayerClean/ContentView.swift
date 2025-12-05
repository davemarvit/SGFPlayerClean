//
//  ContentView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-24
//  Updated: 2025-12-04 (Aligned with Reverted Init Signature)
//  Purpose: Root container switching between 2D and 3D
//

import SwiftUI

struct ContentView: View {
    @StateObject var app = AppModel()
    
    var body: some View {
        Group {
            if app.viewMode == .view2D {
                // MATCHES: init(app: AppModel) from your paste
                ContentView2D(app: app)
            } else {
                // MATCHES: init(app: AppModel)
                ContentView3D(app: app)
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}
