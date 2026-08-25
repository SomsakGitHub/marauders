//
//  MapView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 25/8/2569 BE.
//

import SwiftUI
import MapKit
import CoreLocation

enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic)
        case .hybrid: .hybrid
        case .satellite: .imagery
        }
    }
}

@Observable
private final class LocationManager {
    private let manager = CLLocationManager()

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
}

struct MapView: View {
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedStyle: MapStyleOption = .standard
    @State private var locationManager = LocationManager()

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapStyle(selectedStyle.mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            Picker("Map Style", selection: $selectedStyle) {
                Text("Standard").tag(MapStyleOption.standard)
                Text("Hybrid").tag(MapStyleOption.hybrid)
                Text("Satellite").tag(MapStyleOption.satellite)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onAppear {
            locationManager.requestPermission()
        }
    }
}

#Preview {
    MapView()
}
