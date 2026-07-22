//
//  ContentView.swift
//  SideBackup
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    
    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()
            
            VStack(spacing: 22) {
                if let operation = state.currentOperation {
                    Text(operation == .backup ? "Backing up app data…" : "Restoring app data…")
                        .font(.title2)
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color("Text")))
                        .scaleEffect(1.5)
                } else {
                    Text(String(format: NSLocalizedString("%@ is inactive.", comment: ""),
                                Bundle.main.appName ?? NSLocalizedString("App", comment: "")))
                        .font(.title2)
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                    
                    Text(String(format: NSLocalizedString("Refresh %@ in ben4Store to continue using it.", comment: ""),
                                Bundle.main.appName ?? NSLocalizedString("this app", comment: "")))
                        .font(.body)
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
