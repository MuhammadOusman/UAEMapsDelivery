# OSRM Data Setup Guide - Production Ready Routing

## Overview
This app uses OSRM (Open Source Routing Machine) for high-quality offline turn-by-turn navigation. This guide will help you process UAE map data into OSRM format.

## Required Files for GitHub Release

You need to upload 5 files to GitHub Release v1.0.0:

1. **uae.mbtiles** (~400-700MB) - Map tiles for display
2. **addresses.db** (~50-200MB) - Location search database
3. **style.json** (~100KB) - Map style
4. **uae.osrm** (~150-300MB) - OSRM routing graph
5. **uae.osrm.{edges,nodes,geometry,names}** - OSRM data files

## Prerequisites

### Install Docker
Download and install: https://www.docker.com/products/docker-desktop

### Download UAE Map Data
```bash
# Download UAE OSM data from Geofabrik
wget https://download.geofabrik.de/asia/gcc-states/united-arab-emirates-latest.osm.pbf
# File size: ~80-100MB
```

---

## Step 1: Generate Map Tiles (MBTiles)

```bash
# Pull Tilemaker Docker image
docker pull ghcr.io/systemed/tilemaker:latest

# Generate MBTiles for map display
docker run -v ${PWD}:/data ghcr.io/systemed/tilemaker:latest \
  /data/united-arab-emirates-latest.osm.pbf \
  --output=/data/uae.mbtiles \
  --process=/usr/local/share/tilemaker/resources/process-openmaptiles.lua \
  --config=/usr/local/share/tilemaker/resources/config-openmaptiles.json

# Windows PowerShell:
docker run -v ${PWD}:/data ghcr.io/systemed/tilemaker:latest /data/united-arab-emirates-latest.osm.pbf --output=/data/uae.mbtiles --process=/usr/local/share/tilemaker/resources/process-openmaptiles.lua --config=/usr/local/share/tilemaker/resources/config-openmaptiles.json

# Result: uae.mbtiles (~400-700MB)
# Processing time: 20-40 minutes
```

---

## Step 2: Generate OSRM Routing Data

```bash
# Pull OSRM Docker image
docker pull ghcr.io/project-osrm/osrm-backend:latest

# Extract routing graph
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest \
  osrm-extract -p /opt/car.lua /data/united-arab-emirates-latest.osm.pbf

# Contract the graph (speeds up routing)
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest \
  osrm-contract /data/united-arab-emirates-latest.osrm

# Partition the graph (for MLD algorithm)
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest \
  osrm-partition /data/united-arab-emirates-latest.osrm

# Customize the graph
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest \
  osrm-customize /data/united-arab-emirates-latest.osrm

# Windows PowerShell (run each command separately):
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-extract -p /opt/car.lua /data/united-arab-emirates-latest.osm.pbf
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-contract /data/united-arab-emirates-latest.osrm
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-partition /data/united-arab-emirates-latest.osrm
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-customize /data/united-arab-emirates-latest.osrm

# This creates multiple files:
# - united-arab-emirates-latest.osrm (~150-300MB)
# - united-arab-emirates-latest.osrm.edges
# - united-arab-emirates-latest.osrm.nodes
# - united-arab-emirates-latest.osrm.geometry
# - united-arab-emirates-latest.osrm.names
# - united-arab-emirates-latest.osrm.fileIndex
# - united-arab-emirates-latest.osrm.properties
# - united-arab-emirates-latest.osrm.ebg_nodes
# - united-arab-emirates-latest.osrm.ebg
# - united-arab-emirates-latest.osrm.timestamp

# Rename to uae.osrm (app expects this name):
# Windows PowerShell:
Rename-Item united-arab-emirates-latest.osrm uae.osrm
Rename-Item united-arab-emirates-latest.osrm.edges uae.osrm.edges
Rename-Item united-arab-emirates-latest.osrm.nodes uae.osrm.nodes
Rename-Item united-arab-emirates-latest.osrm.geometry uae.osrm.geometry
Rename-Item united-arab-emirates-latest.osrm.names uae.osrm.names
Rename-Item united-arab-emirates-latest.osrm.fileIndex uae.osrm.fileIndex
Rename-Item united-arab-emirates-latest.osrm.properties uae.osrm.properties
Rename-Item united-arab-emirates-latest.osrm.ebg_nodes uae.osrm.ebg_nodes
Rename-Item united-arab-emirates-latest.osrm.ebg uae.osrm.ebg
Rename-Item united-arab-emirates-latest.osrm.timestamp uae.osrm.timestamp

# Processing time: 15-30 minutes total
```

---

## Step 3: Create Address Database

```bash
# Install osmium tool (if not using Docker)
# Windows: download from https://osmcode.org/osmium-tool/

# Extract addresses to CSV
osmium tags-filter united-arab-emirates-latest.osm.pbf \
  w/highway w/building w/amenity n/place \
  -o uae-addresses.osm.pbf

# Then use Python script (create this file: extract_addresses.py)
```

Create `extract_addresses.py`:

```python
import sqlite3
import osmium

class AddressHandler(osmium.SimpleHandler):
    def __init__(self, conn):
        super().__init__()
        self.conn = conn
        self.cursor = conn.cursor()
        
    def node(self, n):
        if n.tags:
            name = n.tags.get('name')
            addr_full = n.tags.get('addr:full')
            place = n.tags.get('place')
            
            if name or addr_full or place:
                address = addr_full or name or place or ''
                self.cursor.execute('''
                    INSERT INTO addresses (name, address, latitude, longitude, type)
                    VALUES (?, ?, ?, ?, ?)
                ''', (name or address, address, n.location.lat, n.location.lon, place or 'poi'))
    
    def way(self, w):
        if w.tags and len(w.nodes) > 0:
            name = w.tags.get('name')
            highway = w.tags.get('highway')
            
            if name and highway:
                # Get center point
                center = w.nodes[len(w.nodes)//2]
                self.cursor.execute('''
                    INSERT INTO addresses (name, address, latitude, longitude, type)
                    VALUES (?, ?, ?, ?, ?)
                ''', (name, name, center.lat, center.lon, 'street'))

# Create database
conn = sqlite3.connect('addresses.db')
cursor = conn.cursor()

cursor.execute('''
    CREATE TABLE IF NOT EXISTS addresses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        address TEXT,
        latitude REAL,
        longitude REAL,
        type TEXT
    )
''')

cursor.execute('CREATE INDEX IF NOT EXISTS idx_name ON addresses(name)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_lat_lon ON addresses(latitude, longitude)')

# Process OSM data
handler = AddressHandler(conn)
handler.apply_file('uae-addresses.osm.pbf')

conn.commit()
conn.close()

print("Address database created: addresses.db")
```

Run:
```bash
pip install osmium
python extract_addresses.py
```

---

## Step 4: Download Map Style

```bash
# Download OpenMapTiles basic style
wget https://raw.githubusercontent.com/openmaptiles/osm-bright-gl-style/master/style.json

# Or use this minimal style (create style.json):
```

Create `style.json`:

```json
{
  "version": 8,
  "name": "Basic",
  "sources": {
    "openmaptiles": {
      "type": "vector",
      "url": "mbtiles://uae.mbtiles"
    }
  },
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "#f8f4f0"}
    },
    {
      "id": "water",
      "type": "fill",
      "source": "openmaptiles",
      "source-layer": "water",
      "paint": {"fill-color": "#a0c8f0"}
    },
    {
      "id": "roads",
      "type": "line",
      "source": "openmaptiles",
      "source-layer": "transportation",
      "paint": {"line-color": "#ffffff", "line-width": 2}
    },
    {
      "id": "buildings",
      "type": "fill",
      "source": "openmaptiles",
      "source-layer": "building",
      "paint": {"fill-color": "#e0e0e0"}
    }
  ]
}
```

---

## Step 5: Create TAR Archive for OSRM Files

```bash
# Windows PowerShell:
tar -czf osrm_data.tar.gz uae.osrm uae.osrm.* 

# This creates a single compressed archive (~200-400MB) containing all OSRM files
```

---

## Step 6: Upload to GitHub Release

1. Go to: https://github.com/MuhammadOusman/UAEMapsDelivery/releases/new

2. Fill in:
   - **Tag**: `v1.0.0`
   - **Title**: `UAE Maps Data v1.0.0`
   - **Description**: `Offline maps and routing data for UAE`

3. Upload these files:
   - `uae.mbtiles` (~400-700MB)
   - `addresses.db` (~50-200MB)
   - `style.json` (~100KB)
   - `osrm_data.tar.gz` (~200-400MB)

4. Click **Publish release**

---

## Step 7: Update App Constants

The app is already configured! Check `src/utils/constants.ts`:

```typescript
export const GITHUB_REPO = 'MuhammadOusman/UAEMapsDelivery';
export const GITHUB_RELEASE_TAG = 'v1.0.0';

export const DOWNLOAD_URLS = {
  MBTILES: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/uae.mbtiles`,
  ADDRESSES: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/addresses.db`,
  STYLE: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/style.json`,
  OSRM: `https://github.com/${GITHUB_REPO}/releases/download/${GITHUB_RELEASE_TAG}/osrm_data.tar.gz`,
};
```

---

## Testing the App

1. **Install on device**:
   ```bash
   npm run android
   ```

2. **First launch**:
   - App will show download screen
   - Ensure WiFi is connected
   - Total download: ~800MB-1.5GB
   - Takes 5-15 minutes depending on internet speed

3. **Test routing**:
   - Open app
   - Tap on map to set pickup location
   - Tap again to set dropoff location
   - Click "Start Trip"
   - App will calculate route using OSRM
   - Turn-by-turn navigation will begin

---

## Troubleshooting

### OSRM files not loading
- Check that all .osrm files are uploaded to GitHub Release
- Verify file names match exactly: `uae.osrm`, `uae.osrm.edges`, etc.

### Routing fails
- Check device logs: `adb logcat | grep OSRM`
- Ensure OSRM data files are complete (osrm-contract step completed)

### Download fails
- Check WiFi connection
- Verify GitHub Release is public
- Check available device storage (need 2GB free)

---

## File Size Summary

| File | Size | Purpose |
|------|------|---------|
| uae.mbtiles | 400-700MB | Map display |
| addresses.db | 50-200MB | Location search |
| style.json | 100KB | Map styling |
| osrm_data.tar.gz | 200-400MB | All OSRM routing files |
| **Total** | **~800MB-1.5GB** | Full offline functionality |

---

## Processing Time

- **MBTiles generation**: 20-40 minutes
- **OSRM graph creation**: 15-30 minutes
- **Address extraction**: 5-10 minutes
- **Upload to GitHub**: 5-20 minutes (depends on internet)
- **Total**: ~1-2 hours

---

## Production Deployment

Once data is uploaded:

1. **Build release APK**:
   ```bash
   cd android
   ./gradlew assembleRelease
   ```

2. **APK location**:
   `android/app/build/outputs/apk/release/app-release.apk`

3. **Distribute**:
   - Share APK directly
   - Upload to Play Store
   - Use internal distribution (Firebase App Distribution)

---

## Need Help?

Check the app logs for detailed error messages:
```bash
# Android
adb logcat | grep -E "OSRM|DownloadService|RoutingService"

# View downloaded files
adb shell ls -lh /data/user/0/com.uaemapsdelivery/files/map_data/
```

The app uses best-quality OSRM routing with:
- Real road network topology
- Turn-by-turn instructions
- Realistic distance and time estimates
- Completely offline operation
- Fast route calculation (<1 second for most routes)
