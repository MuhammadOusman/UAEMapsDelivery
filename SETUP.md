# UAE Maps Delivery App - Setup Instructions

## Overview
This is a React Native app for delivery riders with **offline UAE maps** and **offline navigation**. No paid APIs required - uses OpenStreetMap data, MapLibre GL, and Valhalla routing engine.

## What YOU Need to Provide

### 1. **GitHub Repository for Map Data Hosting**

Create a GitHub repository to host the map data files:

1. Create a new GitHub repo (e.g., `your-username/uae-maps-data`)
2. Update `src/utils/constants.ts` file:
   ```typescript
   export const GITHUB_REPO = 'your-username/uae-maps-data';
   export const GITHUB_RELEASE_TAG = 'v1.0.0';
   ```

### 2. **Process and Upload Map Data**

You need to prepare 4 files and upload them to a GitHub Release:

#### **File 1: UAE Map Tiles (MBTiles format)**
- **Size:** ~400-700MB
- **Process:**
  1. Download UAE OSM data: https://download.geofabrik.de/asia/gcc-states/united-arab-emirates-latest.osm.pbf
  2. Install Tilemaker: https://github.com/systemed/tilemaker
  3. Generate MBTiles:
     ```bash
     tilemaker --input united-arab-emirates-latest.osm.pbf \
               --output uae.mbtiles \
               --config resources/config-openmaptiles.json \
               --process resources/process-openmaptiles.lua
     ```
  4. Upload `uae.mbtiles` to GitHub Release

#### **File 2: Valhalla Routing Tiles**
- **Size:** ~50-100MB
- **Process:**
  1. Install Valhalla: https://github.com/valhalla/valhalla
  2. Build routing tiles:
     ```bash
     valhalla_build_config --mjolnir-tile-dir ./valhalla_tiles > valhalla.json
     valhalla_build_tiles -c valhalla.json united-arab-emirates-latest.osm.pbf
     ```
  3. Compress the tiles:
     ```bash
     tar -czf valhalla_tiles.tar.gz valhalla_tiles/
     ```
  4. Upload `valhalla_tiles.tar.gz` to GitHub Release

#### **File 3: Address Database (SQLite)**
- **Size:** ~50-200MB
- **Process:**
  1. Extract addresses from OSM data using osmium or custom script
  2. Create SQLite database with schema:
     ```sql
     CREATE TABLE addresses (
       id INTEGER PRIMARY KEY,
       name TEXT NOT NULL,
       address TEXT,
       latitude REAL NOT NULL,
       longitude REAL NOT NULL,
       type TEXT
     );
     CREATE INDEX idx_name ON addresses(name);
     CREATE INDEX idx_location ON addresses(latitude, longitude);
     ```
  3. Upload `addresses.db` to GitHub Release

#### **File 4: Map Style JSON**
- **Size:** ~50-100KB
- **Process:**
  1. Use OpenMapTiles style: https://github.com/openmaptiles/osm-bright-gl-style
  2. Download `style.json` and customize for UAE
  3. Upload `style.json` to GitHub Release

### 3. **Create GitHub Release**

1. Go to your `uae-maps-data` repository
2. Create a new release with tag `v1.0.0`
3. Upload all 4 files:
   - `uae.mbtiles`
   - `valhalla_tiles.tar.gz`
   - `addresses.db`
   - `style.json`
4. Publish the release

## Alternative: Quick Start (Without Processing Data Yourself)

If you don't want to process the data:

### **Option A: Use Mock Data for Development**
The app currently has mock implementations that work without real data. You can test the UI flow.

### **Option B: Use Pre-processed Data Services**
- **Protomaps**: https://protomaps.com (free tier for UAE tiles)
- **Geofabrik OSM Extracts**: Pre-packaged regional data

## Setup Instructions

### 1. Install Dependencies
```bash
cd UAEMapsDelivery
npm install
```

### 2. Configure MapLibre (iOS)
```bash
cd ios
pod install
cd ..
```

Add to `ios/Podfile`:
```ruby
pod 'MapLibre', '~> 6.0'
```

### 3. Android Configuration
Already configured with proper permissions in `AndroidManifest.xml`.

### 4. Update Constants
Edit `src/utils/constants.ts`:
- Set your GitHub repo details
- Adjust download URLs

### 5. Run the App

**iOS:**
```bash
npm run ios
```

**Android:**
```bash
npm run android
```

## Current Implementation Status

### ✅ Implemented
- Project structure with TypeScript
- Download service with progress tracking
- WiFi detection and storage checks
- Location search service (SQLite ready)
- Routing service (Valhalla ready)
- Map display with MapLibre GL
- Turn-by-turn navigation UI
- Trip management (start/end)
- Geolocation tracking
- Route deviation detection and re-routing

### ⚠️ Needs Configuration
- **GitHub repo URLs** in `src/utils/constants.ts`
- **Map data files** uploaded to GitHub Releases
- **MapLibre native module** configuration (may need additional setup)
- **Valhalla native integration** (currently using mock routing)

### 🔧 Optional Enhancements
- Background update checker (API call to GitHub)
- Valhalla native C++ module for actual routing
- Better offline tile extraction (tar.gz native module)
- Voice navigation
- Trip history storage

## Map Data Processing Tools

### Required Tools:
1. **Tilemaker** - OSM to MBTiles: https://github.com/systemed/tilemaker
2. **Valhalla** - Routing engine: https://github.com/valhalla/valhalla
3. **osmium-tool** - OSM data manipulation: https://osmcode.org/osmium-tool/
4. **SQLite** - Database creation

### Processing Environment:
- Linux or macOS recommended (or WSL on Windows)
- ~2-4 hours processing time for full UAE
- ~10GB temporary disk space needed

## Valhalla Integration Options

### **Option 1: Native Module (Production)**
Build a React Native native module that calls Valhalla C++ library directly.

**Pros:** Best performance, truly offline
**Cons:** Complex setup, requires C++ knowledge

### **Option 2: Pre-computed Routes (Quick)**
Pre-calculate common routes and store in database.

**Pros:** Instant routing, no Valhalla needed
**Cons:** Limited to pre-defined routes

### **Option 3: Current Mock (Development)**
Use the current mock routing for testing UI.

**Pros:** Works immediately, good for development
**Cons:** Not accurate, straight-line routing

## File Size Breakdown

| Component | Size | Compressible |
|-----------|------|--------------|
| MBTiles (vector) | ~400-700MB | No (already compressed) |
| Valhalla tiles | ~50-100MB | Yes (tar.gz ~30MB) |
| Address DB | ~50-200MB | Yes (gzip ~20MB) |
| Style JSON | ~50-100KB | Minimal |
| **Total** | **~800MB-1GB** | Can reduce to ~600-700MB |

## Testing Without Real Data

The app will run with mock data:
1. Skip download screen by using mock flag
2. Map will show blank (no tiles)
3. Routing will show straight lines
4. Search will return empty results

This is sufficient for UI/UX testing.

## Production Deployment Checklist

- [ ] Process UAE OSM data to MBTiles
- [ ] Build Valhalla routing tiles
- [ ] Extract and index UAE addresses
- [ ] Create/customize map style JSON
- [ ] Upload all files to GitHub Release
- [ ] Update `constants.ts` with your repo info
- [ ] Test download on real device
- [ ] Implement proper Valhalla native module
- [ ] Add error handling and retry logic
- [ ] Test offline functionality completely
- [ ] Optimize file sizes if needed
- [ ] Set up monthly update pipeline

## Support & Resources

- **Tilemaker docs**: https://github.com/systemed/tilemaker/blob/master/docs/MANUAL.md
- **Valhalla docs**: https://valhalla.readthedocs.io/
- **MapLibre docs**: https://maplibre.org/
- **OpenMapTiles**: https://openmaptiles.org/
- **React Native Maps**: https://github.com/rnmapbox/maps

## Next Steps

1. **Set up your GitHub repository** for map data
2. **Process the map data** OR use mock data for development
3. **Update constants.ts** with your repo information
4. **Test the app** with mock data first
5. **Deploy real data** when ready for production

---

**Contact:** For questions about processing map data or Valhalla integration, you can use open-source community resources or hire a GIS specialist for data processing.
