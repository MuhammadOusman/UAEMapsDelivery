import {DATA_DIR} from '../utils/constants';
import {Route, Location} from '../types';
import OSRMModule from './OSRMModule';

class RoutingService {
  private initialized = false;

  async initialize(): Promise<void> {
    try {
      // Initialize OSRM engine with data from DATA_DIR/osrm
      const osrmPath = `${DATA_DIR}/osrm`;
      await OSRMModule.initialize(osrmPath);
      console.log('OSRM routing service initialized with data from:', osrmPath);
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
      console.log('Calculating route from', from, 'to', to);

      // Call native OSRM module for routing
      const result = await OSRMModule.route(
        { latitude: from.latitude, longitude: from.longitude },
        { latitude: to.latitude, longitude: to.longitude }
      );

      if (!result) {
        return null;
      }

      // Convert OSRM result to our Route format
      const route: Route = {
        coordinates: result.coordinates as [number, number][],
        distance: result.distance,
        duration: result.duration,
        instructions: result.instructions.map(inst => ({
          text: inst.text,
          distance: inst.distance,
          time: inst.time,
          type: inst.type,
          streetName: inst.type === 'depart' ? from.address : 
                     inst.type === 'arrive' ? to.address : undefined,
        })),
      };

      return route;
    } catch (error) {
      console.error('Route calculation error:', error);
      // Fallback to straight line if OSRM fails
      return this.getFallbackRoute(from, to);
    }
  }

  private getFallbackRoute(from: Location, to: Location): Route {
    // Fallback straight line route if OSRM fails
    return {
      coordinates: [
        [from.longitude, from.latitude] as [number, number],
        [to.longitude, to.latitude] as [number, number],
      ],
      distance: this.calculateDistance(from, to),
      duration: this.calculateDistance(from, to) / 10,
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
