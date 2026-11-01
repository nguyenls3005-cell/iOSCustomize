import Foundation
import SwiftUI

final class RunLog: ObservableObject {
    static let shared = RunLog()

    @Published private(set) var lines: [String] = []
    @Published private(set) var firstLineId = 0

    private var pending: [String] = []
    private var flushScheduled = false
    private let lock = NSLock()
    private let windowSize = 600

    private init() {}

    func append(_ line: String) {
        lock.lock()
        pending.append(line)
        let needsFlush = !flushScheduled
        flushScheduled = needsFlush
        lock.unlock()
        guard needsFlush else { return }
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    func clear() {
        lock.lock()
        pending.removeAll()
        flushScheduled = false
        lock.unlock()
        if !lines.isEmpty { lines.removeAll() }
    }

    private func flush() {
        lock.lock()
        let batch = pending
        pending.removeAll()
        flushScheduled = false
        lock.unlock()
        guard !batch.isEmpty else { return }
        lines.append(contentsOf: batch)
        if lines.count > windowSize {
            let dropped = lines.count - windowSize
            lines.removeFirst(dropped)
            firstLineId += dropped
        }
    }
}

/// Card nhật ký — view duy nhất observe RunLog.
/// Bọc trong AppCard để drop thẳng vào ScrollView + LazyVStack.
struct RunLogCard: View {
    @ObservedObject private var log = RunLog.shared
    @State private var followsTail = true

    private static let viewportHeight: CGFloat = 200
    private static let tail = "runlog.tail"

    var body: some View {
        if !log.lines.isEmpty {
            AppCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(
                        icon: "terminal",
                        title: "Nhật ký",
                        trailing: AnyView(
                            HStack(spacing: 8) {
                                Text("\(log.lines.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button("Xoá") { log.clear() }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppPalette.accent)
                            }
                        )
                    )
                    viewport
                }
            }
        }
    }

    private var viewport: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.id) { row in
                        Text(row.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Color.clear.frame(height: 1).id(Self.tail)
                }
                .padding(.vertical, 2)
            }
            .frame(height: Self.viewportHeight)
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottomTrailing) {
                if !followsTail {
                    Button {
                        followsTail = true
                        proxy.scrollTo(Self.tail, anchor: .bottom)
                    } label: {
                        Label("Mới nhất", systemImage: "arrow.down.to.line.compact")
                            .font(.system(size: 11, weight: .bold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(AppPalette.accent)
                    }
                    .buttonStyle(.glass)
                    .tint(AppPalette.accent)
                    .controlSize(.mini)
                    .padding(8)
                }
            }
            .onChange(of: log.lines.count) { _, _ in
                guard followsTail else { return }
                proxy.scrollTo(Self.tail, anchor: .bottom)
            }
            .onChange(of: log.firstLineId) { _, _ in
                guard !followsTail else { return }
                proxy.scrollTo(Self.tail, anchor: .bottom)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 24
            } action: { atEnd, _ in
                if followsTail, !atEnd { followsTail = false }
                else if !followsTail, atEnd { followsTail = true }
            }
            .task {
                guard followsTail else { return }
                proxy.scrollTo(Self.tail, anchor: .bottom)
            }
        }
    }

    private var rows: [(id: Int, text: String)] {
        log.lines.enumerated().map { (log.firstLineId + $0.offset, $0.element) }
    }
}