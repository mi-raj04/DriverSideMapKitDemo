import SwiftUI
import MapKit

extension CLLocationCoordinate2D {
    static let towerBridge = CLLocationCoordinate2D(latitude: 23.071653, longitude: 72.516995)
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var heading: CLHeading?

    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
        self.locationManager.startUpdatingHeading()
    }

    func requestLocation() {
        self.locationManager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        DispatchQueue.main.async {
            self.location = newLocation
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error getting location: \(error.localizedDescription)")
    }
}


struct MapViewRepresentable: UIViewRepresentable {
    var overlays: [MKOverlay] = []
        var showsUserLocation: Bool
        var showAlert: Binding<Bool>
        var isAnimatingCar: Bool
        @ObservedObject var locationManager: LocationManager
        var isLocationBasedRegionEnabled: Bool // Added state variable for controlling location-based region setting

        func makeUIView(context: Context) -> MKMapView {
            let mapView = MKMapView()
            mapView.delegate = context.coordinator
            mapView.showsUserLocation = showsUserLocation
            return mapView
        }
        
        func updateUIView(_ view: MKMapView, context: Context) {
            if !overlays.isEmpty {
                view.removeOverlays(view.overlays)
                view.addOverlays(overlays)
            }

            if isAnimatingCar {
                addCarAnnotation(to: view)
            }

            if let userLocation = locationManager.location {
                let towerBridgeLocation = CLLocationCoordinate2D.towerBridge
                let towerBridgeCLLocation = CLLocation(latitude: towerBridgeLocation.latitude, longitude: towerBridgeLocation.longitude)
                let distance = userLocation.distance(from: towerBridgeCLLocation)

                if distance < 100 { // Adjust the threshold as needed
                    showAlert.wrappedValue = true
                }
            }
            
            // Set the map view's region based on user location if the feature is enabled
            if isLocationBasedRegionEnabled, let userLocation = locationManager.location?.coordinate {
                let region = MKCoordinateRegion(center: userLocation, latitudinalMeters: 100, longitudinalMeters: 100)
                view.setRegion(region, animated: true)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(locationManager: locationManager, parent: self)
        }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var locationManager: LocationManager
        var parent: MapViewRepresentable

        init(locationManager: LocationManager, parent: MapViewRepresentable) {
            self.locationManager = locationManager
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                return renderer
            } else if overlay is MKPolyline {
                let renderer = MKPolylineRenderer(overlay: overlay)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: "userLocation")
                annotationView.image = UIImage(named: "car")?.withTintColor(.blue)
                return annotationView
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let heading = locationManager.heading else { return }
            if let annotationView = mapView.view(for: userLocation) {
                annotationView.transform = CGAffineTransform(rotationAngle: CGFloat(heading.trueHeading.degreesToRadians))
            }
        }
    }

    private func addCarAnnotation(to mapView: MKMapView) {
        guard let userLocation = mapView.userLocation.location else { return }

        let annotation = MKPointAnnotation()
        annotation.coordinate = userLocation.coordinate
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotation(annotation)
    }
}
struct ContentView: View {
    @StateObject var locationManager = LocationManager()
    @State private var isLocationBasedRegionEnabled = true // Track whether the feature is enabled or disabled
    @State private var route: MKRoute?
    @State private var overlays: [MKOverlay] = []
    @State private var showAlert = false
    @State private var isAnimatingCar = false
    
    var body: some View {
        VStack {
            MapViewRepresentable(
                overlays: overlays,
                showsUserLocation: true,
                showAlert: $showAlert,
                isAnimatingCar: isAnimatingCar,
                locationManager: locationManager,
                isLocationBasedRegionEnabled: isLocationBasedRegionEnabled // Pass the state variable to MapViewRepresentable
            )
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                locationManager.requestLocation()
            }
            .onChange(of: locationManager.location) { newLocation in
                guard let newLocation = newLocation else { return }
                calculateRoute(from: newLocation.coordinate)
                isAnimatingCar = true // Start animating car when location updates
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Tower Bridge Alert"), message: Text("You are near Tower Bridge."), dismissButton: .default(Text("OK")))
            }
            
            // Button to toggle location-based region setting
            Button(action: {
                isLocationBasedRegionEnabled.toggle() // Toggle the state variable
            }) {
                Text(isLocationBasedRegionEnabled ? "Disable Location-Based Region" : "Enable Location-Based Region")
            }
            .padding()
        }
    }
    
    func calculateRoute(from coordinate: CLLocationCoordinate2D) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D.towerBridge))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let unwrappedResponse = response else { return }
            
            if let route = unwrappedResponse.routes.first {
                self.route = route
                self.overlays = [route.polyline]
            }
        }
    }
}

extension CLLocationDirection {
    var degreesToRadians: Double { self * .pi / 180 }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension CGFloat {
    var degreesToRadians: CGFloat { self * .pi / 180 }
}
