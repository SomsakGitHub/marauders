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
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStyle: MapStyleOption = .standard
    @State private var locationManager = LocationManager()
    @State private var selectedFriend: Friend?

    private let friends = Friend.samples

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            ForEach(friends) { friend in
                Annotation(friend.name, coordinate: friend.coordinate) {
                    FriendAnnotation(friend: friend, isSelected: selectedFriend?.id == friend.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedFriend = friend
                            }
                        }
                }
            }
        }
        .mapStyle(selectedStyle.mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottom) {
            if let friend = selectedFriend {
                FriendCard(friend: friend) {
                    withAnimation {
                        selectedFriend = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedFriend == nil {
                Picker("Map Style", selection: $selectedStyle) {
                    Text("Standard").tag(MapStyleOption.standard)
                    Text("Hybrid").tag(MapStyleOption.hybrid)
                    Text("Satellite").tag(MapStyleOption.satellite)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            locationManager.requestPermission()
        }
    }
}

struct FriendAnnotation: View {
    let friend: Friend
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(friend.emoji)
                .font(.largeTitle)
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 3)
                .scaleEffect(isSelected ? 1.3 : 1.0)

            Text(friend.name)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

struct FriendCard: View {
    let friend: Friend
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(friend.emoji)
                .font(.title)
                .frame(width: 48, height: 48)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.headline)
                Text("ละติจูด: \(friend.latitude, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ลองจิจูด: \(friend.longitude, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

#Preview {
    MapView()
}
