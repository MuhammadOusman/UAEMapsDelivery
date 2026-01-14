import RNFS from 'react-native-fs';

// GitHub Release URLs - YOU NEED TO UPDATE THESE
export const GITHUB_REPO = 'MuhammadOusman/UAEMapsDelivery';
export const GITHUB_RELEASE_TAG = 'v1.0.0';

export const DOWNLOAD_URLS = {
  MBTILES: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/uae.mbtiles`,
  VALHALLA: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/valhalla_tiles.tar.gz`,
  ADDRESSES: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/addresses.db`,
  STYLE: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/style.json`,
};

// File paths
export const DATA_DIR = `${RNFS.DocumentDirectoryPath}/map_data`;
export const MBTILES_PATH = `${DATA_DIR}/uae.mbtiles`;
export const VALHALLA_DIR = `${DATA_DIR}/valhalla_tiles`;
export const ADDRESSES_DB_PATH = `${DATA_DIR}/addresses.db`;
export const STYLE_PATH = `${DATA_DIR}/style.json`;
export const VERSION_FILE = `${DATA_DIR}/version.txt`;

// Map configuration
export const UAE_CENTER = {
  latitude: 24.4539,
  longitude: 54.3773,
};

export const UAE_BOUNDS = {
  minLat: 22.5,
  maxLat: 26.5,
  minLng: 51.5,
  maxLng: 56.5,
};

// Routing configuration
export const DEVIATION_THRESHOLD = 75; // meters
export const REROUTE_COOLDOWN = 5000; // milliseconds

// Update check
export const UPDATE_CHECK_URL = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;
