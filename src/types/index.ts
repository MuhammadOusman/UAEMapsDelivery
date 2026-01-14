export interface Location {
  latitude: number;
  longitude: number;
  address?: string;
}

export interface Route {
  coordinates: [number, number][];
  distance: number; // in meters
  duration: number; // in seconds
  instructions: RouteInstruction[];
}

export interface RouteInstruction {
  text: string;
  distance: number;
  time: number;
  type: string; // 'turn-left', 'turn-right', 'straight', etc.
  streetName?: string;
}

export interface Trip {
  id: string;
  pickup: Location;
  dropoff: Location;
  route?: Route;
  status: 'pending' | 'active' | 'completed';
  startTime?: Date;
  endTime?: Date;
}

export interface SearchResult {
  id: number;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  type: string; // 'street', 'building', 'poi'
}

export interface DownloadProgress {
  totalBytes: number;
  downloadedBytes: number;
  percentage: number;
  currentFile: string;
}

export type RootStackParamList = {
  Splash: undefined;
  Download: undefined;
  Home: undefined;
  Navigation: {
    trip: Trip;
  };
};
