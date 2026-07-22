//
//  ConsoleLogView.swift
//  AltStore
//
//  Created by Magesh K on 29/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
import SwiftUI

@MainActor
class ConsoleLogViewModel: ObservableObject {
    @Published var logLines: [String] = []
    
    @Published var searchTerm: String = ""
    @Published var currentSearchIndex: Int = 0
    @Published var searchResults: [Int] = []  // Stores indices of matching lines
    
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var logURL: URL
    private var lastReadOffset: UInt64 = 0
    
    init(logURL: URL) {
        self.logURL = logURL
        startFileWatcher() // Start monitoring the log file for changes
        
        Task {
            await reloadLogData(isInitial: true)
        }
    }
    
    private func startFileWatcher() {
        let fileDescriptor = open(logURL.path, O_RDONLY)
        guard fileDescriptor != -1 else {
            debugLog("Unable to open file for reading.")
            return
        }
        
        let queue = DispatchQueue(label: "com.myapp.backgroundQueue", qos: .background)
        fileWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: queue)
        fileWatcher?.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.reloadLogData(isInitial: false)
            }
        }
        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }
        fileWatcher?.resume()
    }
    
    private func reloadLogData(isInitial: Bool) async {
        let logURL = self.logURL
        let lastReadOffset = self.lastReadOffset
        
        let result = await Task.detached(priority: .userInitiated) { () -> (lines: [String], newOffset: UInt64, isReset: Bool)? in
            do {
                let fileHandle = try FileHandle(forReadingFrom: logURL)
                defer { try? fileHandle.close() }
                
                let currentSize = try fileHandle.seekToEnd()
                if isInitial || currentSize < lastReadOffset {
                    try fileHandle.seek(toOffset: 0)
                    if let data = try fileHandle.readToEnd() {
                        let content = String(decoding: data, as: UTF8.self)
                        let lines = content.split(whereSeparator: \.isNewline).map { String($0) }
                        return (lines, currentSize, true)
                    }
                } else if currentSize > lastReadOffset {
                    try fileHandle.seek(toOffset: lastReadOffset)
                    if let data = try fileHandle.readToEnd() {
                        let content = String(decoding: data, as: UTF8.self)
                        let lines = content.split(whereSeparator: \.isNewline).map { String($0) }
                        return (lines, currentSize, false)
                    }
                }
            } catch {
                debugLog("Error reading log file: \(error)")
            }
            return nil
        }.value
        
        guard let result = result else { return }
        
        self.lastReadOffset = result.newOffset
        if result.isReset {
            self.logLines = result.lines
        } else {
            self.logLines.append(contentsOf: result.lines)
        }
    }
    
    deinit {
        fileWatcher?.cancel()
    }
    
    func performSearch() {
        searchResults = logLines.enumerated()
            .filter { $0.element.localizedCaseInsensitiveContains(searchTerm) }
            .map { $0.offset }
    }
    
    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
    }
    
    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
    }
}


public struct ConsoleLogView: View {
    
    @ObservedObject var viewModel: ConsoleLogViewModel
    @State private var scrollToBottom: Bool = false  // State variable to trigger scroll
    @State private var searchBarState: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    
    @State private var searchText: String = ""
    @State private var scrollToIndex: Int?
    @State private var showTimestamp: Bool = false
    @State private var fontSize: CGFloat = 12
    
    private let resultHighlightColor = Color.orange
    private let resultHighlightOpacity = 0.5
    private let otherResultsColor = Color.yellow
    private let otherResultsOpacity = 0.3

    init(logURL: URL) {
        self.viewModel = ConsoleLogViewModel(logURL: logURL)
    }
    
    public var body: some View {
       VStack {
           
           // Custom Header Bar (similar to QuickLook's preview screen)
           HStack(spacing: 12) {
               Text("Console Log")
                   .font(.system(size: 22, weight: .semibold))
                   .foregroundColor(.white)
               Spacer()
               
               if(!searchBarState){
                   SwiftUI.Button(action: {
                       searchBarState.toggle()
                   }) {
                       Image(systemName: "magnifyingglass")
                           .foregroundColor(.white)
                           .imageScale(.large)
                   }
               }

                SwiftUI.Button(action: {
                    fontSize = max(6, fontSize - 1)
                }) {
                    Image(systemName: "minus")
                        .foregroundColor(.white)
                        .imageScale(.medium)
                }
                
                SwiftUI.Button(action: {
                    fontSize = min(30, fontSize + 1)
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .imageScale(.medium)
                }
                
                SwiftUI.Button(action: {
                    showTimestamp.toggle()
                }) {
                    Image(systemName: showTimestamp ? "clock.fill" : "clock")
                        .foregroundColor(.white)
                        .font(.system(size: 19))
                }
                
                SwiftUI.Button(action: {
                    scrollToBottom.toggle()
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .imageScale(.large)
                }
           }
           .padding(15)
           .padding(.top, 5)
           .padding(.bottom, 2.5)
           .background(Color.black.opacity(0.9))
           .overlay(
               Rectangle()
                   .frame(height: 1)
                   .foregroundColor(Color.gray.opacity(0.2)), alignment: .bottom
           )

           if(searchBarState){
               // Search bar
              HStack {
                  Image(systemName: "magnifyingglass")
                      .foregroundColor(.gray)
                      .padding(.trailing, 4)

                  TextField("Search", text: $searchText)
                      .textFieldStyle(RoundedBorderTextFieldStyle())
                      .onChange(of: searchText) { _, newValue in
                          viewModel.searchTerm = newValue
                          viewModel.performSearch()
                      }
                      .keyboardShortcut("f", modifiers: .command) // Focus search field
                  
                  if !searchText.isEmpty {
                      // Search navigation buttons
                      SwiftUI.Button(action: {
                          viewModel.previousSearchResult()
                          scrollToIndex = viewModel.searchResults[viewModel.currentSearchIndex]
                      }) {
                          Image(systemName: "chevron.up")
                      }
                      .keyboardShortcut(.return, modifiers: [.command, .shift])
                      .disabled(viewModel.searchResults.isEmpty)
                      
                      SwiftUI.Button(action: {
                          viewModel.nextSearchResult()
                          scrollToIndex = viewModel.searchResults[viewModel.currentSearchIndex]
                      }) {
                          Image(systemName: "chevron.down")
                      }
                      .keyboardShortcut(.return, modifiers: .command)
                      .disabled(viewModel.searchResults.isEmpty)

                      // Results counter
                      Text("\(viewModel.currentSearchIndex + 1)/\(viewModel.searchResults.count)")
                          .foregroundColor(.gray)
                          .font(.caption)
                  }
                  
                  SwiftUI.Button(action: {
                      searchBarState.toggle()
                  }) {
                      Image(systemName: "xmark")
                  }
              }
              .padding(.horizontal, 15)
           }

           

           // Main Log Display (scrollable area)
            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.logLines.indices, id: \.self) { index in
                            let line = viewModel.logLines[index]
                            let displayLine = showTimestamp ? line : stripTimestamp(from: line)
                            Text(displayLine)
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundColor(.white)
                                .background(
                                    viewModel.searchResults.contains(index) ?
                                    otherResultsColor.opacity(otherResultsOpacity) : Color.clear
                                )
                                .background(
                                    viewModel.searchResults[safe: viewModel.currentSearchIndex] == index ?
                                    resultHighlightColor.opacity(resultHighlightOpacity) : Color.clear
                                )
                        }
                    }
                    .onChange(of: scrollToIndex) { _, newIndex in
                        if let index = newIndex {
                            withAnimation {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: scrollToBottom) { _, _ in
                        viewModel.logLines.indices.last.map { last in
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black)  // Set background color to mimic QL's dark theme
        .edgesIgnoringSafeArea(.all)
    }

    private static let timestampRegex = try? NSRegularExpression(
        pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3} \\[[A-Z]\\]: ",
        options: []
    )

    private func stripTimestamp(from line: String) -> String {
        guard let regex = Self.timestampRegex else { return line }
        let range = NSRange(location: 0, length: line.utf16.count)
        if let match = regex.firstMatch(in: line, range: range) {
            let matchRange = Range(match.range, in: line)!
            return String(line[matchRange.upperBound...])
        }
        return line
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
