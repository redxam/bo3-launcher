import Foundation
import AppKit

struct WorkshopItem {
    let id: String
    let title: String
    let previewURL: String?

    var workshopURL: URL {
        URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!
    }
}

actor SteamWorkshop {
    private var cache: [String: WorkshopItem] = [:]

    static var isSteamRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.valvesoftware.steam").isEmpty
    }

    static func launchSteam() {
        guard let url = URL(string: "steam://open/main") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the item in the Steam client, where Unsubscribe lives.
    static func openWorkshopPage(id: String) {
        guard let url = URL(string: "steam://url/CommunityFilePage/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    func fetchDetails(ids: [String]) async -> [String: WorkshopItem] {
        let uncached = ids.filter { cache[$0] == nil }
        if !uncached.isEmpty {
            let fetched = await batchFetch(uncached)
            for (id, item) in fetched {
                cache[id] = item
            }
        }
        return ids.reduce(into: [:]) { result, id in
            result[id] = cache[id]
        }
    }

    private func batchFetch(_ ids: [String]) async -> [String: WorkshopItem] {
        let url = URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!

        var body = "itemcount=\(ids.count)"
        for (i, id) in ids.enumerated() {
            body += "&publishedfileids[\(i)]=\(id)"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var result: [String: WorkshopItem] = [:]
        var needsFallback: [String] = []

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? [String: Any],
               let details = response["publishedfiledetails"] as? [[String: Any]] {
                for detail in details {
                    guard let id = detail["publishedfileid"] as? String else { continue }
                    let code = detail["result"] as? Int ?? 0
                    if code == 1, let title = detail["title"] as? String {
                        let preview = detail["preview_url"] as? String
                        result[id] = WorkshopItem(id: id, title: title, previewURL: preview)
                    } else {
                        needsFallback.append(id)
                    }
                }
            }
        } catch {
            needsFallback = ids
        }

        for id in ids where result[id] == nil && !needsFallback.contains(id) {
            needsFallback.append(id)
        }

        let scraped = await scrapeTitles(needsFallback)
        for (id, item) in scraped {
            result[id] = item
        }

        return result
    }

    private func scrapeTitles(_ ids: [String]) async -> [String: WorkshopItem] {
        var result: [String: WorkshopItem] = [:]
        await withTaskGroup(of: (String, WorkshopItem).self) { group in
            for id in ids {
                group.addTask { await (id, self.scrapeTitle(id)) }
            }
            for await (id, item) in group {
                result[id] = item
            }
        }
        return result
    }

    private nonisolated func scrapeTitle(_ id: String) async -> WorkshopItem {
        let url = URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8),
               let titleRange = html.range(of: "<title>"),
               let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
                var title = String(html[titleRange.upperBound..<endRange.lowerBound])
                if let workshopPrefix = title.range(of: "Steam Workshop::") {
                    title = String(title[workshopPrefix.upperBound...])
                }
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return WorkshopItem(id: id, title: title, previewURL: nil)
                }
            }
        } catch {}
        return WorkshopItem(id: id, title: id, previewURL: nil)
    }
}
