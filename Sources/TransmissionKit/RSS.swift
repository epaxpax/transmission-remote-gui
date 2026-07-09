import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A single entry parsed from an RSS/Atom feed.
public struct RSSItem: Sendable, Hashable, Identifiable {
    public let title: String
    /// Download link — a magnet URI or a `.torrent` URL (from `<link>`, `<enclosure url>`, or Atom `<link href>`).
    public let link: String
    /// Stable identifier for dedup (`<guid>` / Atom `<id>`, falling back to the link).
    public let guid: String

    public var id: String { guid }

    public init(title: String, link: String, guid: String) {
        self.title = title
        self.link = link
        self.guid = guid
    }
}

/// Minimal RSS 2.0 / Atom feed parser (SAX via `XMLParser`). Extracts torrent items:
/// title + download link (magnet or .torrent) + a dedup id. No external dependency.
public final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var inItem = false
    private var element = ""
    private var text = ""
    private var curTitle = ""
    private var curLink = ""
    private var curGuid = ""
    private var curEnclosure = ""

    public static func parse(_ data: Data) -> [RSSItem] {
        let p = RSSParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        return p.items
    }

    public func parser(_ parser: XMLParser, didStartElement name: String,
                       namespaceURI: String?, qualifiedName qName: String?,
                       attributes attrs: [String: String]) {
        element = name
        text = ""
        if name == "item" || name == "entry" {
            inItem = true
            curTitle = ""; curLink = ""; curGuid = ""; curEnclosure = ""
        }
        // Atom <link href="…">, and RSS <enclosure url="…"> carry the URL in an attribute.
        if inItem, name == "link", let href = attrs["href"], !href.isEmpty {
            curLink = href
        }
        if inItem, name == "enclosure", let url = attrs["url"], !url.isEmpty {
            curEnclosure = url
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { text += s }
    }

    public func parser(_ parser: XMLParser, didEndElement name: String,
                       namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch name {
            case "title": curTitle = value
            case "link": if curLink.isEmpty { curLink = value }   // RSS <link>text</link>
            case "guid", "id": curGuid = value
            case "item", "entry":
                // Prefer an explicit torrent/magnet link; fall back to the enclosure URL.
                let dl = !curLink.isEmpty ? curLink : curEnclosure
                if !curTitle.isEmpty, !dl.isEmpty {
                    let guid = !curGuid.isEmpty ? curGuid : dl
                    items.append(RSSItem(title: curTitle, link: dl, guid: guid))
                }
                inItem = false
            default: break
            }
        }
        text = ""
    }
}
