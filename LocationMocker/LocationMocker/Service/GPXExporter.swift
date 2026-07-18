import Foundation
import CoreLocation

enum GPXExporter {

    /// Generate a GPX file string from a list of waypoints.
    static func generateGPX(
        name: String,
        points: [RoutePoint],
        includeTimestamps: Bool = true,
        speedMs: Float = 0,
        intervalSeconds: TimeInterval = 1.0
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"
             creator="LocationMocker iOS"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <trk>
            <name>\(name.escapedXML)</name>
            <trkseg>
        """

        let now = Date()
        for (index, point) in points.enumerated() {
            let timestamp = includeTimestamps
                ? now.addingTimeInterval(Double(index) * intervalSeconds)
                : nil
            xml += """

                  <trkpt lat="\(point.lat)" lon="\(point.lon)">
            """
            if let alt = point.altitude {
                xml += """

                    <ele>\(alt)</ele>
                """
            }
            if let time = timestamp {
                xml += """

                    <time>\(ISO8601DateFormatter().string(from: time))</time>
                """
            }
            if speedMs > 0 {
                xml += """

                    <speed>\(speedMs)</speed>
                """
            }
            xml += """

                  </trkpt>
            """
        }

        xml += """

            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }

    /// Generate a GPX containing waypoints (for single-point simulation in Xcode).
    static func generateWaypointGPX(name: String, point: RoutePoint) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"
             creator="LocationMocker iOS"
             xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="\(point.lat)" lon="\(point.lon)">
            <name>\(name.escapedXML)</name>
            \(point.altitude.map { "<ele>\($0)</ele>" } ?? "")
          </wpt>
        </gpx>
        """
    }

    /// Save GPX to a file and return the URL.
    static func saveGPX(_ content: String, fileName: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let url = docs?.appendingPathComponent("\(fileName).gpx")
        guard let url else { return nil }
        try? FileManager.default.removeItem(at: url)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to write GPX: \(error)")
            return nil
        }
    }
}

private extension String {
    var escapedXML: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
