import SwiftUI
import TransmissionKit

/// RSS auto-downloader manager: master switch, watched feeds, download rules,
/// and a manual "check now" button.
struct RSSView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var newFeedName = ""
    @State private var newFeedURL = ""
    @State private var newRule = ""

    var body: some View {
        @Bindable var rss = model.rss
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(loc("RSS auto-letöltő")).font(.title2.bold())
                Spacer()
                Button(loc("Kész")) { dismiss() }.keyboardShortcut(.defaultAction)
            }

            Toggle(loc("Automatikus letöltés bekapcsolása"), isOn: $rss.enabled)
                .toggleStyle(.switch)

            // MARK: Feeds
            GroupBox(loc("Hírcsatornák (feed-ek)")) {
                VStack(alignment: .leading, spacing: 6) {
                    if rss.feeds.isEmpty {
                        Text(loc("Nincs feed. Adj hozzá egyet lentebb.")).foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach($rss.feeds) { $feed in
                        HStack {
                            Toggle("", isOn: $feed.enabled).labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(feed.name).lineLimit(1)
                                Text(feed.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { rss.feeds.removeAll { $0.id == feed.id } } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        TextField(loc("Név"), text: $newFeedName).frame(width: 120)
                        TextField(loc("Feed URL"), text: $newFeedURL)
                        Button(loc("Hozzáad")) {
                            let n = newFeedName.trimmingCharacters(in: .whitespaces)
                            let u = newFeedURL.trimmingCharacters(in: .whitespaces)
                            guard !u.isEmpty else { return }
                            rss.feeds.append(RSSFeed(name: n.isEmpty ? u : n, url: u))
                            newFeedName = ""; newFeedURL = ""
                        }.disabled(newFeedURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }.padding(6)
            }

            // MARK: Rules
            GroupBox(loc("Szabályok (cím-szűrő)")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("Ha egy tétel címe illik egy aktív szabályra, automatikusan letöltődik. Szöveg = tartalmazás; /minta/ = regex.")).font(.caption).foregroundStyle(.secondary)
                    ForEach($rss.rules) { $rule in
                        HStack {
                            Toggle("", isOn: $rule.enabled).labelsHidden()
                            Text(rule.pattern).font(.callout.monospaced())
                            Spacer()
                            Button { rss.rules.removeAll { $0.id == rule.id } } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        TextField(loc("Új szabály (pl. 1080p vagy /S0[12]E../)"), text: $newRule)
                        Button(loc("Hozzáad")) {
                            let p = newRule.trimmingCharacters(in: .whitespaces)
                            guard !p.isEmpty else { return }
                            rss.rules.append(RSSRule(pattern: p))
                            newRule = ""
                        }.disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }.padding(6)
            }

            HStack {
                Button(loc("Frissítés most")) { Task { await model.rssPoll() } }
                    .disabled(!model.isConnected || !rss.enabled)
                Spacer()
                Text(loc("Ellenőrzés 15 percenként")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 540, height: 580)
    }
}
