import {VALHALLA_DIR} from '../utils/constants';
import {Route, Location} from '../types';

// This is a placeholder for Valhalla integration
// You'll need to implement native module bindings or use a pre-built library

class RoutingService {
  private initialized = false;

  async initialize(): Promise<void> {
    try {
      // TODO: Initialize Valhalla engine with tiles from VALHALLA_DIR
      // For now, this is a mock implementation
      console.log('Routing service initialized with tiles from:', VALHALLA_DIR);
      this.initialized = true;
    } catch (error) {
      console.error('Routing initialization error:', error);
      throw error;
    }
  }

  async calculateRoute(from: Location, to: Location): Promise<Route | null> {
    if (!this.initialized) {
      await this.initialize();
    }

    try {
      // TODO: Implement actual Valhalla route calculation
      // This is a mock implementation that returns a simple straight line
      
      console.log('Calculating route from', from, 'to', to);

      // Mock route for demonstration
      // In production, this should call Valhalla native module
      const route: Route = {
        coordinates: [
          [from.longitude, from.latitude],
          [to.longitude, to.latitude],
        ],
        distance: this.calculateDistance(from, to),
        duration: this.calculateDistance(from, to) / 10, // ~36 km/h average
        instructions: [
          {
            text: 'Start your journey',
            distance: 0,
            time: 0,
            type: 'start',
            streetName: from.address,
          },
          {
            text: `Head towards ${to.address}`,
            distance: this.calculateDistance(from, to) * 0.8,
            time: (this.calculateDistance(from, to) / 10) * 0.8,
            type: 'straight',
          },
          {
            text: 'You have arrived at your destination',
            distance: this.calculateDistance(from, to),
            time: this.calculateDistance(from, to) / 10,
            type: 'arrive',
            streetName: to.address,
          },
        ],
      };

      return route;
    } catch (error) {
      console.error('Route calculation error:', error);
      return null;
    }
  }

  private calculateDistance(from: Location, to: Location): number {
    // Haversine formula for distance calculation
    const R = 6371e3; // Earth radius in meters
    const φ1 = (from.latitude * Math.PI) / 180;
    const φ2 = (to.latitude * Math.PI) / 180;
    const Δφ = ((to.latitude - from.latitude) * Math.PI) / 180;
    const Δλ = ((to.longitude - from.longitude) * Math.PI) / 180;

    const a =
      Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
      Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c; // Distance in meters
  }

  calculateDistanceBetweenPoints(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
    return this.calculateDistance(
      {latitude: lat1, longitude: lon1},
      {latitude: lat2, longitude: lon2},
    );
  }
}

export default new RoutingService();
