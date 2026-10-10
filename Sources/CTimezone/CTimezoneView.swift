import CTimezoneKit
import SwiftUI

struct CTimezoneView: View {
    @State private var model = CTimezoneModel()

    var body: some View {
        NavigationSplitView {
            zoneSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "City or region")
        .frame(minWidth: 720, minHeight: 600)
        .onAppear { model.refresh() }
    }

    // MARK: - Sidebar

    private var zoneSidebar: some View {
        ScrollViewReader { proxy in
            List(model.filteredCatalog, id: \.self, selection: $model.selectedTimeZone) { zone in
                ZoneRow(zone: zone, isConfigured: zone == model.cliConfiguredTZ)
                    .tag(zone)
                    .accessibilityIdentifier("ctz.zone.\(zone)")
            }
            .accessibilityIdentifier("ctz.zoneList")
            .onAppear {
                if let zone = model.selectedTimeZone {
                    proxy.scrollTo(zone, anchor: .center)
                }
            }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Form {
            Section {
                WorldMapView(
                    mac: model.systemZone.identifier.flatMap { model.locations[$0] },
                    claude: model.previewIdentifier.flatMap { model.locations[$0] }
                )
                .frame(maxWidth: 640, maxHeight: 230)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                ClockComparison(
                    systemZone: model.systemZone.identifier,
                    systemSource: systemZoneDetail,
                    claudeZone: model.previewIdentifier,
                    isPreview: model.hasUnappliedSelection
                )
            }

            Section {
                targetRow(title: "Claude Code + URL Handler") {
                    codeDetail
                } actions: {
                    if model.cliConfiguredTZ != nil {
                        Button("Use System") {
                            Task { await model.resetToSystemTimeZone() }
                        }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("ctz.resetButton")
                    }
                    Button("Apply") {
                        Task { await model.apply() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || !model.hasUnappliedSelection)
                    .accessibilityIdentifier("ctz.applyButton")
                }

                targetRow(title: "Claude Desktop") {
                    desktopDetail
                } actions: {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh status")
                    .accessibilityLabel("Refresh")
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("ctz.refreshButton")
                    Button(model.desktopStatus.isRunning && !model.desktopIsInSync ? "Relaunch" : "Open") {
                        Task { await model.launchDesktop() }
                    }
                    .disabled(model.isBusy || model.desktopTargetIdentifier == nil)
                    .accessibilityIdentifier("ctz.launchButton")
                }
            } footer: {
                Text("Claude Code reads env.TZ from ~/.claude/settings.json; restart sessions to apply. Desktop only gets a launch environment, never what Claude detects on its servers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let banner = model.banner {
                Section {
                    bannerView(banner)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("CTimeZone")
        .navigationSubtitle("Claude's clock, not your Mac's")
    }

    private func targetRow<Detail: View, Actions: View>(
        title: String,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                detail()
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { actions() }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var codeDetail: some View {
        if model.hasUnappliedSelection, let pending = model.selectedTimeZone {
            Text("\(model.cliConfiguredTZ ?? "System") \u{2192} ") + Text(pending).foregroundStyle(Color.accentColor)
        } else {
            Text(model.cliConfiguredTZ ?? "Using the system time zone")
                .accessibilityIdentifier("ctz.configuredValue")
        }
    }

    private var desktopDetail: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(desktopStatusColor)
                .frame(width: 7, height: 7)
            Text(desktopStatusText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ctz.desktopStatus")
    }

    private var systemZoneDetail: String {
        switch model.systemZone.source {
        case .systemLink: return "System"
        case .processFallback: return "Process fallback"
        case .unknown: return "Unknown"
        }
    }

    private var desktopStatusText: String {
        let target = model.desktopModeLabel
        guard model.desktopStatus.isRunning else { return "Not running \u{00B7} opens in \(target)" }
        if model.desktopIsInSync { return "Running in \(target)" }
        switch model.desktopStatus.observedTZ {
        case .value(let tz): return "Running in \(tz) \u{00B7} relaunch for \(target)"
        case .absent: return "Running in system zone \u{00B7} relaunch for \(target)"
        case .unavailable: return "Running, zone unreadable \u{00B7} target \(target)"
        }
    }

    private var desktopStatusColor: Color {
        guard model.desktopStatus.isRunning else { return .secondary.opacity(0.5) }
        return model.desktopIsInSync ? .green : .orange
    }

    private func bannerView(_ banner: CTimezoneModel.Banner) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: banner.kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.kind == .error ? Color.red : Color.green)
            Text(banner.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.banner = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .accessibilityIdentifier("ctz.banner")
    }
}

// MARK: - Zone row

private struct ZoneRow: View {
    let zone: String
    let isConfigured: Bool

    var body: some View {
        let parts = zone.split(separator: "/")
        let city = (parts.last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ")
        let region = parts.dropLast().joined(separator: " / ").replacingOccurrences(of: "_", with: " ")

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(city)
                    .lineLimit(1)
                if !region.isEmpty {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isConfigured {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Saved")
            }
            Text(GMTOffset.label(for: zone))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Clocks

private struct ClockComparison: View {
    let systemZone: String?
    let systemSource: String
    let claudeZone: String?
    let isPreview: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .center, spacing: 0) {
                ClockFace(
                    caption: "This Mac · \(systemSource)",
                    zone: systemZone,
                    date: context.date,
                    emphasized: false
                )
                .accessibilityIdentifier("ctz.systemClock")

                deltaBadge(at: context.date)
                    .padding(.horizontal, 12)

                ClockFace(
                    caption: isPreview ? "Claude · preview" : "Claude",
                    zone: claudeZone,
                    date: context.date,
                    emphasized: true
                )
                .accessibilityIdentifier("ctz.targetClock")
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func deltaBadge(at date: Date) -> some View {
        if let a = systemZone.flatMap(TimeZone.init(identifier:)),
           let b = claudeZone.flatMap(TimeZone.init(identifier:)) {
            let seconds = b.secondsFromGMT(for: date) - a.secondsFromGMT(for: date)
            Text(GMTOffset.delta(seconds))
                .font(.callout.monospacedDigit().weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("Difference \(GMTOffset.delta(seconds))")
        } else {
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
        }
    }
}

private struct ClockFace: View {
    let caption: String
    let zone: String?
    let date: Date
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let zone, let tz = TimeZone(identifier: zone) {
                Text(date.formatted(Self.time(in: tz)))
                    .font(.system(size: 28, weight: emphasized ? .semibold : .regular, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(emphasized ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(date.formatted(Self.day(in: tz)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(zone)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("--:--:--")
                    .font(.system(size: 30, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("Unknown zone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private static func time(in tz: TimeZone) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .standard)
        style.timeZone = tz
        return style
    }

    private static func day(in tz: TimeZone) -> Date.FormatStyle {
        var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = tz
        return style
    }
}

// MARK: - Offset formatting

private enum GMTOffset {
    /// "GMT+8", "GMT−3:30", "GMT".
    static func label(for zone: String, at date: Date = .now) -> String {
        guard let tz = TimeZone(identifier: zone) else { return "" }
        let seconds = tz.secondsFromGMT(for: date)
        return seconds == 0 ? "GMT" : "GMT" + signed(seconds)
    }

    /// "+6h", "−2:30h", "Same time".
    static func delta(_ seconds: Int) -> String {
        seconds == 0 ? "Same time" : signed(seconds) + "h"
    }

    private static func signed(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "\u{2212}" : "+"
        let minutes = abs(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(sign)\(h)" : String(format: "%@%d:%02d", sign, h, m)
    }
}
