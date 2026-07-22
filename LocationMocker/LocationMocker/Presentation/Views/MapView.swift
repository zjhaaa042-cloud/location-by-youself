import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject var viewModel: MainViewModel

    @State private var mapType: MKMapType = .standard
    @State private var showMapPicker = false

    var body: some View {
        MapReader { proxy in
            Map(position: mapPosition) {
                // Route polyline
                if viewModel.routePolyline.count >= 2 {
                    MapPolyline(coordinates: viewModel.routePolyline.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    })
                    .stroke(.blue, lineWidth: 3)
                }

                // Track preview (aiming / adjusting / running)
                if viewModel.trackPreview.count >= 2 {
                    MapPolyline(coordinates: viewModel.trackPreview.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    })
                    .stroke(.green, lineWidth: 4)
                }

                // Track start flag (fine-tuning stage)
                if viewModel.trackSetupMode == .adjusting, let start = viewModel.trackStartPoint {
                    Annotation("起点", coordinate: CLLocationCoordinate2D(
                        latitude: start.lat,
                        longitude: start.lon
                    )) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(6)
                            .background(Circle().fill(.white).shadow(radius: 2))
                    }
                }

                // Markers
                ForEach(Array(viewModel.markers.enumerated()), id: \.offset) { index, point in
                    Marker("点\(index + 1)", coordinate: CLLocationCoordinate2D(
                        latitude: point.lat,
                        longitude: point.lon
                    ))
                    .tint(index == 0 ? .green : .red)
                }

                // Current simulated location
                if let loc = viewModel.currentLocation {
                    Annotation("当前位置", coordinate: CLLocationCoordinate2D(
                        latitude: loc.lat,
                        longitude: loc.lon
                    )) {
                        Image(systemName: "location.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                            .background(Circle().fill(.white).padding(2))
                    }
                }
            }
            .mapStyle(mapType == .satellite ? .imagery : .standard)
            // 相机实时同步回 viewModel.mapRegion（iOS 17+），
            // 保证「以地图中心生成跑道」用的是用户松手时真正的视野中心
            .onMapCameraChange(frequency: .continuous) { context in
                viewModel.mapRegion = context.region
            }
            .onTapGesture { position in
                // 瞄准/微调模式下点击地图不再误加标记点
                guard viewModel.trackSetupMode == .off else { return }
                if let coordinate = proxy.convert(position, from: .local) {
                    viewModel.addMarker(at: coordinate)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            mapTypeButton
                .padding(.top, 52)
                .padding(.trailing, 12)
        }
    }

    private var mapPosition: Binding<MapCameraPosition> {
        Binding(
            get: { .region(viewModel.mapRegion) },
            set: {
                if let region = $0.region {
                    viewModel.mapRegion = region
                }
            }
        )
    }

    private var mapTypeButton: some View {
        Menu {
            Button("标准地图") { mapType = .standard }
            Button("卫星地图") { mapType = .satellite }
        } label: {
            Image(systemName: "map.fill")
                .font(.title3)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}
