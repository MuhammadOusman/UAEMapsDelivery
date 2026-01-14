import React, {useState, useRef, useEffect} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  FlatList,
  Keyboard,
  Alert,
  ActivityIndicator,
} from 'react-native';
import {NativeStackScreenProps} from '@react-navigation/native-stack';
import MapLibreGL from '@rnmapbox/maps';
import {RootStackParamList, Location, SearchResult, Trip} from '../types';
import LocationSearchService from '../services/LocationSearchService';
import RoutingService from '../services/RoutingService';
import {UAE_CENTER, STYLE_PATH, MBTILES_PATH} from '../utils/constants';

type Props = NativeStackScreenProps<RootStackParamList, 'Home'>;

// Set MapLibre access token (not needed for offline, but required by library)
MapLibreGL.setAccessToken(null);

const HomeScreen: React.FC<Props> = ({navigation}) => {
  const [pickup, setPickup] = useState<Location | null>(null);
  const [dropoff, setDropoff] = useState<Location | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [searchMode, setSearchMode] = useState<'pickup' | 'dropoff' | null>(null);
  const [calculating, setCalculating] = useState(false);
  const mapRef = useRef<MapLibreGL.MapView>(null);
  const cameraRef = useRef<MapLibreGL.Camera>(null);

  useEffect(() => {
    initializeServices();
  }, []);

  const initializeServices = async () => {
    try {
      await LocationSearchService.initialize();
      await RoutingService.initialize();
    } catch (error) {
      console.error('Service initialization error:', error);
      Alert.alert('Error', 'Failed to initialize services');
    }
  };

  const handleSearch = async (query: string) => {
    setSearchQuery(query);
    if (query.length >= 2) {
      const results = await LocationSearchService.search(query);
      setSearchResults(results);
    } else {
      setSearchResults([]);
    }
  };

  const handleSelectLocation = (result: SearchResult) => {
    const location: Location = {
      latitude: result.latitude,
      longitude: result.longitude,
      address: result.name,
    };

    if (searchMode === 'pickup') {
      setPickup(location);
    } else if (searchMode === 'dropoff') {
      setDropoff(location);
    }

    // Move camera to location
    cameraRef.current?.setCamera({
      centerCoordinate: [result.longitude, result.latitude],
      zoomLevel: 14,
      animationDuration: 1000,
    });

    setSearchQuery('');
    setSearchResults([]);
    setSearchMode(null);
    Keyboard.dismiss();
  };

  const handleMapPress = (feature: any) => {
    if (searchMode) {
      const [longitude, latitude] = feature.geometry.coordinates;
      const location: Location = {
        latitude,
        longitude,
        address: 'Selected location',
      };

      if (searchMode === 'pickup') {
        setPickup(location);
      } else if (searchMode === 'dropoff') {
        setDropoff(location);
      }

      setSearchMode(null);
    }
  };

  const handleStartTrip = async () => {
    if (!pickup || !dropoff) {
      Alert.alert('Error', 'Please select both pickup and dropoff locations');
      return;
    }

    setCalculating(true);

    try {
      const route = await RoutingService.calculateRoute(pickup, dropoff);
      
      if (!route) {
        Alert.alert('Error', 'Failed to calculate route');
        setCalculating(false);
        return;
      }

      const trip: Trip = {
        id: Date.now().toString(),
        pickup,
        dropoff,
        route,
        status: 'active',
        startTime: new Date(),
      };

      setCalculating(false);
      navigation.navigate('Navigation', {trip});
    } catch (error) {
      console.error('Route calculation error:', error);
      Alert.alert('Error', 'Failed to calculate route');
      setCalculating(false);
    }
  };

  const renderSearchResult = ({item}: {item: SearchResult}) => (
    <TouchableOpacity
      style={styles.searchResultItem}
      onPress={() => handleSelectLocation(item)}>
      <Text style={styles.searchResultName}>{item.name}</Text>
      <Text style={styles.searchResultAddress}>{item.address}</Text>
    </TouchableOpacity>
  );

  return (
    <View style={styles.container}>
      <MapLibreGL.MapView
        ref={mapRef}
        style={styles.map}
        styleURL={`file://${STYLE_PATH}`}
        onPress={handleMapPress}>
        <MapLibreGL.Camera
          ref={cameraRef}
          zoomLevel={10}
          centerCoordinate={[UAE_CENTER.longitude, UAE_CENTER.latitude]}
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

        {/* Pickup marker */}
        {pickup && (
          <MapLibreGL.MarkerView coordinate={[pickup.longitude, pickup.latitude]}>
            <View style={[styles.marker, styles.pickupMarker]}>
              <Text style={styles.markerText}>P</Text>
            </View>
          </MapLibreGL.MarkerView>
        )}

        {/* Dropoff marker */}
        {dropoff && (
          <MapLibreGL.MarkerView coordinate={[dropoff.longitude, dropoff.latitude]}>
            <View style={[styles.marker, styles.dropoffMarker]}>
              <Text style={styles.markerText}>D</Text>
            </View>
          </MapLibreGL.MarkerView>
        )}
      </MapLibreGL.MapView>

      {/* Search UI */}
      <View style={styles.searchContainer}>
        {searchMode ? (
          <>
            <View style={styles.searchInputContainer}>
              <TextInput
                style={styles.searchInput}
                placeholder={`Search ${searchMode} location...`}
                value={searchQuery}
                onChangeText={handleSearch}
                autoFocus
              />
              <TouchableOpacity
                style={styles.cancelButton}
                onPress={() => {
                  setSearchMode(null);
                  setSearchQuery('');
                  setSearchResults([]);
                  Keyboard.dismiss();
                }}>
                <Text style={styles.cancelButtonText}>Cancel</Text>
              </TouchableOpacity>
            </View>
            {searchResults.length > 0 && (
              <FlatList
                data={searchResults}
                renderItem={renderSearchResult}
                keyExtractor={item => item.id.toString()}
                style={styles.searchResultsList}
                keyboardShouldPersistTaps="handled"
              />
            )}
          </>
        ) : (
          <View style={styles.locationButtons}>
            <TouchableOpacity
              style={styles.locationButton}
              onPress={() => setSearchMode('pickup')}>
              <Text style={styles.locationButtonLabel}>Pickup</Text>
              <Text style={styles.locationButtonValue}>
                {pickup?.address || 'Tap to select'}
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.locationButton}
              onPress={() => setSearchMode('dropoff')}>
              <Text style={styles.locationButtonLabel}>Dropoff</Text>
              <Text style={styles.locationButtonValue}>
                {dropoff?.address || 'Tap to select'}
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.startButton,
                (!pickup || !dropoff || calculating) && styles.startButtonDisabled,
              ]}
              onPress={handleStartTrip}
              disabled={!pickup || !dropoff || calculating}>
              {calculating ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.startButtonText}>Start Trip</Text>
              )}
            </TouchableOpacity>
          </View>
        )}
      </View>

      {searchMode && (
        <View style={styles.mapHint}>
          <Text style={styles.mapHintText}>
            Or tap on the map to select a location
          </Text>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  map: {
    flex: 1,
  },
  searchContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    backgroundColor: '#fff',
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.2,
    shadowRadius: 4,
  },
  searchInputContainer: {
    flexDirection: 'row',
    padding: 12,
    alignItems: 'center',
  },
  searchInput: {
    flex: 1,
    height: 44,
    borderWidth: 1,
    borderColor: '#DDD',
    borderRadius: 8,
    paddingHorizontal: 12,
    fontSize: 16,
  },
  cancelButton: {
    marginLeft: 8,
    paddingHorizontal: 12,
  },
  cancelButtonText: {
    color: '#007AFF',
    fontSize: 16,
    fontWeight: '500',
  },
  searchResultsList: {
    maxHeight: 300,
    backgroundColor: '#fff',
  },
  searchResultItem: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#EEE',
  },
  searchResultName: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
    marginBottom: 4,
  },
  searchResultAddress: {
    fontSize: 14,
    color: '#666',
  },
  locationButtons: {
    padding: 12,
  },
  locationButton: {
    backgroundColor: '#F5F5F5',
    padding: 12,
    borderRadius: 8,
    marginBottom: 8,
  },
  locationButtonLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  locationButtonValue: {
    fontSize: 16,
    color: '#333',
    fontWeight: '500',
  },
  startButton: {
    backgroundColor: '#007AFF',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  startButtonDisabled: {
    backgroundColor: '#CCC',
  },
  startButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
  marker: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 3,
    borderColor: '#fff',
  },
  pickupMarker: {
    backgroundColor: '#4CAF50',
  },
  dropoffMarker: {
    backgroundColor: '#F44336',
  },
  markerText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
  mapHint: {
    position: 'absolute',
    bottom: 20,
    left: 20,
    right: 20,
    backgroundColor: 'rgba(0,0,0,0.7)',
    padding: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  mapHintText: {
    color: '#fff',
    fontSize: 14,
  },
});

export default HomeScreen;
