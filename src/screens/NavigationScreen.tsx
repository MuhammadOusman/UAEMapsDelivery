import React, {useState, useRef, useEffect} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  Platform,
} from 'react-native';
import {NativeStackScreenProps} from '@react-navigation/native-stack';
import MapLibreGL from '@maplibre/maplibre-react-native';
import Geolocation from '@react-native-community/geolocation';
import {RootStackParamList, Trip, Location} from '../types';
import RoutingService from '../services/RoutingService';
import {STYLE_PATH, MBTILES_PATH, DEVIATION_THRESHOLD} from '../utils/constants';

type Props = NativeStackScreenProps<RootStackParamList, 'Navigation'>;

const NavigationScreen: React.FC<Props> = ({route, navigation}) => {
  const {trip: initialTrip} = route.params;
  const [trip, setTrip] = useState<Trip>(initialTrip);
  const [currentLocation, setCurrentLocation] = useState<Location | null>(null);
  const [currentInstructionIndex, setCurrentInstructionIndex] = useState(0);
  const [distanceToNext, setDistanceToNext] = useState(0);
  const [isRerouting, setIsRerouting] = useState(false);
  const mapRef = useRef<any>(null);
  const cameraRef = useRef<any>(null);
  const watchIdRef = useRef<number | null>(null);

  useEffect(() => {
    startLocationTracking();
    return () => {
      stopLocationTracking();
    };
  }, []);

  useEffect(() => {
    if (currentLocation && trip.route) {
      updateNavigationState();
      checkForDeviation();
    }
  }, [currentLocation]);

  const startLocationTracking = () => {
    watchIdRef.current = Geolocation.watchPosition(
      position => {
        const location: Location = {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
        };
        setCurrentLocation(location);

        // Update camera to follow user
        cameraRef.current?.setCamera({
          centerCoordinate: [location.longitude, location.latitude],
          zoomLevel: 16,
          pitch: 60,
          animationDuration: 500,
        });
      },
      error => {
        console.error('Location error:', error);
        Alert.alert('Location Error', 'Failed to get current location');
      },
      {
        enableHighAccuracy: true,
        distanceFilter: 10,
        interval: 1000,
        fastestInterval: 500,
      },
    );
  };

  const stopLocationTracking = () => {
    if (watchIdRef.current !== null) {
      Geolocation.clearWatch(watchIdRef.current);
    }
  };

  const updateNavigationState = () => {
    if (!currentLocation || !trip.route) return;

    const instructions = trip.route.instructions;
    let closestInstructionIndex = 0;
    let minDistance = Infinity;

    // Find closest instruction
    for (let i = 0; i < instructions.length; i++) {
      const instruction = instructions[i];
      // Use first coordinate of route segment for each instruction
      const instrCoord = trip.route.coordinates[Math.min(i, trip.route.coordinates.length - 1)];
      const distance = RoutingService.calculateDistanceBetweenPoints(
        currentLocation.latitude,
        currentLocation.longitude,
        instrCoord[1],
        instrCoord[0],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestInstructionIndex = i;
      }
    }

    setCurrentInstructionIndex(closestInstructionIndex);
    setDistanceToNext(minDistance);

    // Check if arrived
    const distanceToDestination = RoutingService.calculateDistanceBetweenPoints(
      currentLocation.latitude,
      currentLocation.longitude,
      trip.dropoff.latitude,
      trip.dropoff.longitude,
    );

    if (distanceToDestination < 50) {
      handleArrival();
    }
  };

  const checkForDeviation = async () => {
    if (!currentLocation || !trip.route || isRerouting) return;

    // Calculate distance to route
    let minDistanceToRoute = Infinity;
    for (const coord of trip.route.coordinates) {
      const distance = RoutingService.calculateDistanceBetweenPoints(
        currentLocation.latitude,
        currentLocation.longitude,
        coord[1],
        coord[0],
      );
      minDistanceToRoute = Math.min(minDistanceToRoute, distance);
    }

    // If deviated too far, recalculate route
    if (minDistanceToRoute > DEVIATION_THRESHOLD) {
      await recalculateRoute();
    }
  };

  const recalculateRoute = async () => {
    if (!currentLocation || isRerouting) return;

    setIsRerouting(true);

    try {
      const newRoute = await RoutingService.calculateRoute(
        currentLocation,
        trip.dropoff,
      );

      if (newRoute) {
        setTrip(prev => ({
          ...prev,
          route: newRoute,
        }));
      }
    } catch (error) {
      console.error('Reroute error:', error);
    } finally {
      setTimeout(() => setIsRerouting(false), 3000);
    }
  };

  const handleArrival = () => {
    Alert.alert(
      'Arrived!',
      'You have reached your destination.',
      [
        {
          text: 'End Trip',
          onPress: handleEndTrip,
        },
      ],
      {cancelable: false},
    );
  };

  const handleEndTrip = () => {
    const completedTrip: Trip = {
      ...trip,
      status: 'completed',
      endTime: new Date(),
    };

    Alert.alert('Trip Completed', 'Trip has been completed successfully!', [
      {
        text: 'OK',
        onPress: () => navigation.navigate('Home'),
      },
    ]);
  };

  const formatDistance = (meters: number): string => {
    if (meters < 1000) {
      return `${Math.round(meters)} m`;
    }
    return `${(meters / 1000).toFixed(1)} km`;
  };

  const formatDuration = (seconds: number): string => {
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) {
      return `${minutes} min`;
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return `${hours}h ${remainingMinutes}m`;
  };

  const currentInstruction =
    trip.route?.instructions[currentInstructionIndex];

  return (
    <View style={styles.container}>
      <MapLibreGL.MapView ref={mapRef} style={styles.map}>
        <MapLibreGL.Camera
          ref={cameraRef}
          followUserLocation
          zoomLevel={16}
          pitch={60}
        />

        {/* Offline tile source */}
        <MapLibreGL.RasterSource
          id="offlineTiles"
          tileUrlTemplates={[`mbtiles://${MBTILES_PATH}/{z}/{x}/{y}.pbf`]}
          tileSize={512}>
          <MapLibreGL.RasterLayer 
            id="offlineTilesLayer" 
            sourceID="offlineTiles"
            style={{rasterOpacity: 1}} 
          />
        </MapLibreGL.RasterSource>

        {/* Route line */}
        {trip.route && (
          <MapLibreGL.ShapeSource
            id="routeSource"
            shape={{
              type: 'Feature',
              geometry: {
                type: 'LineString',
                coordinates: trip.route.coordinates,
              },
              properties: {},
            }}>
            <MapLibreGL.LineLayer
              id="routeLine"
              style={{
                lineColor: '#007AFF',
                lineWidth: 6,
                lineCap: 'round',
                lineJoin: 'round',
              }}
            />
          </MapLibreGL.ShapeSource>
        )}

        {/* User location */}
        <MapLibreGL.UserLocation
          visible
          showsUserHeadingIndicator
          minDisplacement={10}
        />

        {/* Destination marker */}
        <MapLibreGL.MarkerView
          coordinate={[trip.dropoff.longitude, trip.dropoff.latitude]}>
          <View style={styles.destinationMarker}>
            <Text style={styles.markerText}>🏁</Text>
          </View>
        </MapLibreGL.MarkerView>
      </MapLibreGL.MapView>

      {/* Navigation instructions */}
      <View style={styles.instructionContainer}>
        {isRerouting && (
          <View style={styles.reroutingBanner}>
            <Text style={styles.reroutingText}>Recalculating route...</Text>
          </View>
        )}

        {currentInstruction && (
          <>
            <View style={styles.instructionBox}>
              <Text style={styles.maneuverIcon}>
                {getManeuverIcon(currentInstruction.type)}
              </Text>
              <View style={styles.instructionTextContainer}>
                <Text style={styles.instructionText}>
                  {currentInstruction.text}
                </Text>
                {currentInstruction.streetName && (
                  <Text style={styles.streetName}>
                    {currentInstruction.streetName}
                  </Text>
                )}
              </View>
            </View>

            <View style={styles.distanceBox}>
              <Text style={styles.distanceText}>
                {formatDistance(distanceToNext)}
              </Text>
              <Text style={styles.distanceLabel}>to next turn</Text>
            </View>
          </>
        )}

        {trip.route && (
          <View style={styles.routeInfo}>
            <Text style={styles.routeInfoText}>
              {formatDistance(trip.route.distance)} •{' '}
              {formatDuration(trip.route.duration)}
            </Text>
          </View>
        )}
      </View>

      {/* End trip button */}
      <TouchableOpacity style={styles.endButton} onPress={handleEndTrip}>
        <Text style={styles.endButtonText}>End Trip</Text>
      </TouchableOpacity>
    </View>
  );
};

const getManeuverIcon = (type: string): string => {
  const icons: {[key: string]: string} = {
    start: '🚀',
    straight: '⬆️',
    'turn-left': '⬅️',
    'turn-right': '➡️',
    'slight-left': '↖️',
    'slight-right': '↗️',
    'sharp-left': '↩️',
    'sharp-right': '↪️',
    arrive: '🏁',
  };
  return icons[type] || '⬆️';
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  map: {
    flex: 1,
  },
  instructionContainer: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 50 : 20,
    left: 12,
    right: 12,
  },
  reroutingBanner: {
    backgroundColor: '#FF9800',
    padding: 12,
    borderRadius: 8,
    marginBottom: 8,
  },
  reroutingText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
    textAlign: 'center',
  },
  instructionBox: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.2,
    shadowRadius: 4,
    marginBottom: 8,
  },
  maneuverIcon: {
    fontSize: 36,
    marginRight: 12,
  },
  instructionTextContainer: {
    flex: 1,
  },
  instructionText: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 4,
  },
  streetName: {
    fontSize: 14,
    color: '#666',
  },
  distanceBox: {
    backgroundColor: '#007AFF',
    padding: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginBottom: 8,
  },
  distanceText: {
    color: '#fff',
    fontSize: 24,
    fontWeight: 'bold',
  },
  distanceLabel: {
    color: '#fff',
    fontSize: 12,
  },
  routeInfo: {
    backgroundColor: 'rgba(255,255,255,0.9)',
    padding: 8,
    borderRadius: 8,
    alignItems: 'center',
  },
  routeInfoText: {
    fontSize: 14,
    color: '#666',
  },
  destinationMarker: {
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  markerText: {
    fontSize: 32,
  },
  endButton: {
    position: 'absolute',
    bottom: 30,
    left: 20,
    right: 20,
    backgroundColor: '#F44336',
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.2,
    shadowRadius: 4,
  },
  endButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
});

export default NavigationScreen;
