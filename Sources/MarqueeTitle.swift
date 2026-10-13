import AppKit
import SwiftUI

struct MarqueeTitle: View {
    let text: String
    var fontSize: CGFloat = 15
    var weight: NSFont.Weight = .semibold
    var lineHeight: CGFloat = 19
    // Explicit storage avoids the SDK State macro requirement in the command-line build.
    private var startedAt = State<Date>(initialValue: Date())
    private var font: NSFont { .systemFont(ofSize: fontSize, weight: weight) }

    var body: some View {
        GeometryReader { geometry in
            let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            let overflows = textWidth > geometry.size.width + 0.5
            let distance = textWidth + 28
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !overflows)) { timeline in
                // A second copy makes the wrap seamless; each pass pauses at the title's start.
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt.wrappedValue))
                let phase = elapsed.truncatingRemainder(dividingBy: 1.4 + distance / 24)
                let offset = overflows ? -max(0, phase - 1.4) * 24 : 0
                HStack(spacing: 28) {
                    title
                    if overflows { title }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset)
            }
            // Text measurement never participates in the panel's proposed width.
            .frame(width: geometry.size.width, height: lineHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: lineHeight)
        .onAppear { startedAt.wrappedValue = Date() }
        .onChange(of: text) { _, _ in startedAt.wrappedValue = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .help(text)
    }

    private var title: some View {
        Text(text).font(Font(font)).lineLimit(1)
            .shadow(color: .black.opacity(0.65), radius: 0.85, y: 0.5)
    }
}
