//
//  MemosGraphWidget.swift
//  MemosGraphWidget
//
//  Created by Mudkip on 2022/11/11.
//

import WidgetKit
import SwiftUI
import Intents
import KeychainSwift

struct Provider: IntentTimelineProvider {
    func placeholder(in context: Context) -> MemosGraphEntry {
        MemosGraphEntry(date: Date(), configuration: MemosGraphWidgetConfigurationIntent(), matrix: nil)
    }

    func getSnapshot(for configuration: MemosGraphWidgetConfigurationIntent, in context: Context, completion: @escaping (MemosGraphEntry) -> ()) {
        Task { @MainActor in
            var matrix: [DailyUsageStat]?
            if !context.isPreview {
                matrix = try? await getMatrix()
            }
            
            let entry = MemosGraphEntry(date: Date(), configuration: configuration, matrix: matrix)
            completion(entry)
        }
    }
    
    func getMatrix() async throws -> [DailyUsageStat]? {
        guard let host = UserDefaults(suiteName: groupContainerIdentifier)?.string(forKey: memosHostKey) else {
            return nil
        }
        guard let hostURL = URL(string: host) else {
            return nil
        }
        
        let keychain = KeychainSwift()
        keychain.accessGroup = keychainAccessGroupName
        let accessToken = keychain.get(memosAccessTokenKey)
        
        let openId = UserDefaults(suiteName: groupContainerIdentifier)?.string(forKey: memosOpenIdKey)
        
        let memos = try await Memos.create(host: hostURL, accessToken: accessToken, openId: openId)
        
        let response = try await memos.listMemos(data: MemosListMemo.Input(creatorId: nil, rowStatus: .normal, visibility: nil))
        return DailyUsageStat.calculateMatrix(memoList: response)
    }

    func getTimeline(for configuration: MemosGraphWidgetConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task { @MainActor in
            let matrix = try? await getMatrix()
            let entryDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            let entry = MemosGraphEntry(date: entryDate, configuration: configuration, matrix: matrix)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
}

struct MemosGraphEntry: TimelineEntry {
    let date: Date
    let configuration: MemosGraphWidgetConfigurationIntent
    let matrix: [DailyUsageStat]?
}

struct MemosGraphEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        Heatmap(matrix: entry.matrix ?? DailyUsageStat.initialMatrix, alignment: .center)
            .padding()
    }
}

struct MemosGraphWidget: Widget {
    let kind: String = "MemosGraphWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: MemosGraphWidgetConfigurationIntent.self, provider: Provider()) { entry in
            MemosGraphEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
        .configurationDisplayName("widget.memo-graph")
        .description("widget.memo-graph.description")
        .contentMarginsDisabled()
    }
}

struct MemosGraphWidget_Previews: PreviewProvider {
    static var previews: some View {
        MemosGraphEntryView(entry: MemosGraphEntry(date: Date(), configuration: MemosGraphWidgetConfigurationIntent(), matrix: nil))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
