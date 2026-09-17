import SwiftUI
import HarbourCore

struct StatusTrendsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Display clock only: ages the window even when stopped. Never collects data.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    static func stateText(history: StatusHistory, monitoring: Bool, failed: Bool, now: Date) -> String {
        if failed { return "讀取未成功／資料無效；保留的讀數不是即時狀態" }
        if !monitoring { return "未在監察／已停止；只顯示已接收快照" }
        if history.latestTimestamp == nil { return "等待第一份有效快照" }
        if !history.isFresh(now: now) { return "資料已過時（超過 10 秒未更新）；等待新快照" }
        return "監察中；顯示最近收到的採樣，並非連續量測"
    }

    private func content(now: Date) -> some View {
        let history = model.statusHistory
        let latest = history.visibleSamples(now: now).last
        return GroupBox("最近 60 秒趨勢（本次讀取／監察）") {
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.stateText(history: history, monitoring: model.watch && model.runner.busy,
                                    failed: model.statusReadFailed, now: now))
                    .font(.caption).foregroundColor(.secondary)
                if let date = history.latestTimestamp {
                    HStack(spacing: 4) {
                        Text("最後有效採樣：")
                        Text(date, style: .date)
                        Text(date, style: .time)
                    }.font(.caption).monospacedDigit()
                } else {
                    Text("最後有效採樣：尚無資料").font(.caption)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    chart("CPU", metric: .cpu, unit: "%", color: .blue, upperBound: 100, latest: latest, now: now)
                    chart("記憶體", metric: .memory, unit: "%", color: .purple, upperBound: 100, latest: latest, now: now)
                    chart("網絡 RX（接收）", metric: .rx, unit: "MiB/s", color: .green,
                          upperBound: history.networkUpperBound(now: now), latest: latest, now: now)
                    chart("網絡 TX（傳送）", metric: .tx, unit: "MiB/s", color: .orange,
                          upperBound: history.networkUpperBound(now: now), latest: latest, now: now)
                }
                Text("依 collected_at 排列最近 60 秒內最多 \(history.pointCap) 點；約每 2 秒採樣，實際間隔會變動。缺值或間隔超過 6 秒會斷線；不補值。")
                Text("網絡為回報介面之和：目前引擎排除部分虛擬介面，只回報流量最高的最多 3 個；不是全機去重總流量。VPN／重疊介面可能重複計算。單位依引擎換算為 MiB/s（1024² bytes/s）。")
                Text("缺漏／無效值顯示未知，不等於 0；引擎本身的估算或不可用零值未必可區分。停止後資料仍會移出時間窗，不會繼續採樣。")
            }.font(.caption).fixedSize(horizontal: false, vertical: true).padding(6)
        }
    }

    private func chart(_ title: String, metric: StatusMetric, unit: String, color: Color,
                       upperBound: Double, latest: StatusSample?, now: Date) -> some View {
        let segments = model.statusHistory.segments(for: metric, now: now, upperBound: upperBound)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(latest?.value(for: metric).map { String(format: "%.1f %@", $0, unit) } ?? "未知")
                    .monospacedDigit()
            }
            Text("最近採樣值 · 縱軸 0–\(String(format: "%.1f", upperBound)) \(unit)")
                .font(.caption2).foregroundColor(.secondary)
            StatusTrace(segments: segments, color: color).frame(height: 64)
                .accessibilityLabel("\(title)趨勢；\(segments.isEmpty ? "沒有有效樣本" : "按真實採樣時間繪製")")
            HStack { Text("−60 秒"); Spacer(); Text("現在") }
                .font(.caption2).foregroundColor(.secondary)
        }.padding(8).background(Color.primary.opacity(0.04)).cornerRadius(8)
    }
}

private struct StatusTrace: View {
    let segments: [[StatusPlotPoint]]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Inset so flat 0/100 lines and isolated points are not clipped.
                Path { path in
                    for segment in segments {
                        for (index, point) in segment.enumerated() {
                            let position = position(point, size: geometry.size)
                            if index == 0 { path.move(to: position) }
                            else { path.addLine(to: position) }
                        }
                    }
                }.stroke(color, lineWidth: 1.5)
                Path { path in
                    for segment in segments {
                        for point in segment {
                            let position = position(point, size: geometry.size)
                            path.addEllipse(in: CGRect(x: position.x - 1.5, y: position.y - 1.5, width: 3, height: 3))
                        }
                    }
                }.fill(color)
                if segments.isEmpty { Text("沒有有效樣本").font(.caption).foregroundColor(.secondary) }
            }
        }
    }

    private func position(_ point: StatusPlotPoint, size: CGSize) -> CGPoint {
        CGPoint(x: 2 + CGFloat(point.x) * max(0, size.width - 4),
                y: 2 + CGFloat(point.y) * max(0, size.height - 4))
    }
}
