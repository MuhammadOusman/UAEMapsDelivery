import SQLite, {SQLiteDatabase} from 'react-native-sqlite-storage';
import {ADDRESSES_DB_PATH} from '../utils/constants';
import {SearchResult} from '../types';

SQLite.enablePromise(true);

class LocationSearchService {
  private db: SQLiteDatabase | null = null;

  async initialize(): Promise<void> {
    try {
      this.db = await SQLite.openDatabase({
        name: 'addresses.db',
        location: 'default',
        createFromLocation: ADDRESSES_DB_PATH,
      });
      console.log('Database opened successfully');
    } catch (error) {
      console.error('Database initialization error:', error);
      throw error;
    }
  }

  async search(query: string, limit: number = 20): Promise<SearchResult[]> {
    if (!this.db) {
      await this.initialize();
    }

    if (!query || query.length < 2) {
      return [];
    }

    try {
      const searchTerm = `%${query.toLowerCase()}%`;
      
      // Query should match the structure of your addresses database
      // Adjust column names as needed based on your actual database schema
      const [results] = await this.db!.executeSql(
        `SELECT 
          id, 
          name, 
          address, 
          latitude, 
          longitude, 
          type 
        FROM addresses 
        WHERE LOWER(name) LIKE ? OR LOWER(address) LIKE ?
        ORDER BY 
          CASE 
            WHEN LOWER(name) LIKE ? THEN 1
            WHEN LOWER(address) LIKE ? THEN 2
            ELSE 3
          END,
          name ASC
        LIMIT ?`,
        [searchTerm, searchTerm, `${query.toLowerCase()}%`, `${query.toLowerCase()}%`, limit],
      );

      const locations: SearchResult[] = [];
      for (let i = 0; i < results.rows.length; i++) {
        const row = results.rows.item(i);
        locations.push({
          id: row.id,
          name: row.name,
          address: row.address,
          latitude: row.latitude,
          longitude: row.longitude,
          type: row.type,
        });
      }

      return locations;
    } catch (error) {
      console.error('Search error:', error);
      return [];
    }
  }

  async getNearbyLocations(
    latitude: number,
    longitude: number,
    radiusKm: number = 2,
    limit: number = 10,
  ): Promise<SearchResult[]> {
    if (!this.db) {
      await this.initialize();
    }

    try {
      // Simple bounding box search (more efficient than haversine for large datasets)
      const latOffset = radiusKm / 111; // 1 degree latitude ≈ 111km
      const lngOffset = radiusKm / (111 * Math.cos((latitude * Math.PI) / 180));

      const [results] = await this.db!.executeSql(
        `SELECT 
          id, 
          name, 
          address, 
          latitude, 
          longitude, 
          type,
          ((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) as distance
        FROM addresses 
        WHERE latitude BETWEEN ? AND ?
          AND longitude BETWEEN ? AND ?
        ORDER BY distance ASC
        LIMIT ?`,
        [
          latitude,
          latitude,
          longitude,
          longitude,
          latitude - latOffset,
          latitude + latOffset,
          longitude - lngOffset,
          longitude + lngOffset,
          limit,
        ],
      );

      const locations: SearchResult[] = [];
      for (let i = 0; i < results.rows.length; i++) {
        const row = results.rows.item(i);
        locations.push({
          id: row.id,
          name: row.name,
          address: row.address,
          latitude: row.latitude,
          longitude: row.longitude,
          type: row.type,
        });
      }

      return locations;
    } catch (error) {
      console.error('Nearby search error:', error);
      return [];
    }
  }

  async close(): Promise<void> {
    if (this.db) {
      await this.db.close();
      this.db = null;
    }
  }
}

export default new LocationSearchService();
