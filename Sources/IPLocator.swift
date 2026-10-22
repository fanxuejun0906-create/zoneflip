import Foundation

struct ExitInfo {
    let ip: String
    let country: String
    let city: String
    let timezone: String
}

/// Minimal ipinfo.io lookup. No account, no key, no data kept anywhere.
enum IPLocator {
    static func fetch(completion: @escaping (ExitInfo?) -> Void) {
        guard let url = URL(string: "https://ipinfo.io/json") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("ZoneFlip/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard
                let data,
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                completion(nil)
                return
            }
            let info = ExitInfo(
                ip: object["ip"] as? String ?? "?",
                country: object["country"] as? String ?? "",
                city: object["city"] as? String ?? "",
                timezone: object["timezone"] as? String ?? ""
            )
            completion(info)
        }.resume()
    }
}
