# Map Data Processing Guide

This guide walks you through processing OpenStreetMap data for the UAE into the required formats for offline maps and navigation.

## Prerequisites

### Required Software

1. **Docker** (easiest way to run tools)
   - Download: https://www.docker.com/products/docker-desktop

2. **OR Install Tools Manually:**
   - Tilemaker: https://github.com/systemed/tilemaker
   - Valhalla: https://github.com/valhalla/valhalla
   - osmium-tool: https://osmcode.org/osmium-tool/
   - SQLite: https://www.sqlite.org/

### System Requirements
- 10GB free disk space
- 8GB RAM minimum
- 2-4 hours processing time

## Step-by-Step Processing

### Step 1: Download UAE OSM Data

```bash
# Download UAE OSM extract from Geofabrik
wget https://download.geofabrik.de/asia/gcc-states/united-arab-emirates-latest.osm.pbf

# File size: ~80-100MB
```

### Step 2: Generate Map Tiles (MBTiles)

#### Option A: Using Docker (Recommended)

```bash
# Pull Tilemaker Docker image
docker pull ghcr.io/systemed/tilemaker:latest

# Generate MBTiles
docker run -v $(pwd):/data ghcr.io/systemed/tilemaker:latest \
  /data/united-arab-emirates-latest.osm.pbf \
  --output=/data/uae.mbtiles \
  --process=/usr/local/share/tilemaker/resources/process-openmaptiles.lua \
  --config=/usr/local/share/tilemaker/resources/config-openmaptiles.json

# Result: uae.mbtiles (~400-700MB)
```

#### Option B: Manual Installation

```bash
# Install Tilemaker (Ubuntu/Debian)
sudo apt-get install tilemaker

# Generate MBTiles
tilemaker --input united-arab-emirates-latest.osm.pbf \
          --output uae.mbtiles \
          --process resources/process-openmaptiles.lua \
          --config resources/config-openmaptiles.json
```

### Step 3: Build Valhalla Routing Tiles

#### Using Docker (Recommended)

```bash
# Pull Valhalla Docker image
docker pull ghcr.io/valhalla/valhalla:latest

# Create working directory
mkdir -p valhalla_tiles

# Build Valhalla config
docker run -v $(pwd):/data ghcr.io/valhalla/valhalla:latest \
  valhalla_build_config \
  --mjolnir-tile-dir /data/valhalla_tiles \
  --mjolnir-tile-extract /data/valhalla_tiles.tar \
  --mjolnir-timezone /data/valhalla_tiles/timezones.sqlite \
  --mjolnir-admin /data/valhalla_tiles/admins.sqlite > valhalla.json

# Build routing tiles
docker run -v $(pwd):/data ghcr.io/valhalla/valhalla:latest \
  valhalla_build_tiles \
  -c /data/valhalla.json \
  /data/united-arab-emirates-latest.osm.pbf

# Compress tiles
tar -czf valhalla_tiles.tar.gz valhalla_tiles/

# Result: valhalla_tiles.tar.gz (~50-100MB)
```

### Step 4: Extract Address Database

#### Using Python Script

Create `extract_addresses.py`:

```python
import osmium
import sqlite3
import sys

class AddressHandler(osmium.SimpleHandler):
    def __init__(self, db_path):
        osmium.SimpleHandler.__init__(self)
        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()
        self.setup_database()
        self.count = 0
        
    def setup_database(self):
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS addresses (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                address TEXT,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                type TEXT
            )
        ''')
        self.cursor.execute('CREATE INDEX IF NOT EXISTS idx_name ON addresses(name)')
        self.cursor.execute('CREATE INDEX IF NOT EXISTS idx_location ON addresses(latitude, longitude)')
        self.conn.commit()
    
    def node(self, n):
        if not n.tags:
            return
            
        name = n.tags.get('name')
        if not name:
            return
        
        # Build address
        address_parts = []
        for key in ['addr:street', 'addr:district', 'addr:city']:
            if key in n.tags:
                address_parts.append(n.tags[key])
        
        address = ', '.join(address_parts) if address_parts else None
        
        # Determine type
        node_type = 'poi'
        if 'amenity' in n.tags:
            node_type = 'amenity'
        elif 'shop' in n.tags:
            node_type = 'shop'
        elif 'addr:street' in n.tags:
            node_type = 'address'
        
        self.cursor.execute('''
            INSERT INTO addresses (name, address, latitude, longitude, type)
            VALUES (?, ?, ?, ?, ?)
        ''', (name, address, n.location.lat, n.location.lon, node_type))
        
        self.count += 1
        if self.count % 10000 == 0:
            print(f"Processed {self.count} addresses...")
            self.conn.commit()
    
    def way(self, w):
        if not w.tags or not w.nodes:
            return
        
        name = w.tags.get('name')
        if not name:
            return
        
        # Calculate centroid
        lat_sum = sum(n.lat for n in w.nodes)
        lon_sum = sum(n.lon for n in w.nodes)
        lat_avg = lat_sum / len(w.nodes)
        lon_avg = lon_sum / len(w.nodes)
        
        # Build address
        address_parts = []
        for key in ['addr:street', 'addr:district', 'addr:city']:
            if key in w.tags:
                address_parts.append(w.tags[key])
        
        address = ', '.join(address_parts) if address_parts else None
        
        # Determine type
        way_type = 'street'
        if 'building' in w.tags:
            way_type = 'building'
        elif 'highway' in w.tags:
            way_type = 'street'
        
        self.cursor.execute('''
            INSERT INTO addresses (name, address, latitude, longitude, type)
            VALUES (?, ?, ?, ?, ?)
        ''', (name, address, lat_avg, lon_avg, way_type))
        
        self.count += 1
        if self.count % 10000 == 0:
            print(f"Processed {self.count} addresses...")
            self.conn.commit()
    
    def close(self):
        self.conn.commit()
        self.conn.close()
        print(f"Total addresses: {self.count}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python extract_addresses.py input.osm.pbf output.db")
        sys.exit(1)
    
    handler = AddressHandler(sys.argv[2])
    handler.apply_file(sys.argv[1], locations=True)
    handler.close()
```

Run the script:

```bash
# Install dependencies
pip install osmium

# Extract addresses
python extract_addresses.py united-arab-emirates-latest.osm.pbf addresses.db

# Result: addresses.db (~50-200MB)
```

### Step 5: Download Map Style

```bash
# Download OpenMapTiles style
wget https://raw.githubusercontent.com/openmaptiles/osm-bright-gl-style/master/style.json -O style.json

# Customize for local tiles (edit style.json):
# Replace "sources" URLs with local paths
# Adjust zoom levels if needed

# Result: style.json (~50-100KB)
```

## Quick Alternative: Pre-built Tiles

If you don't want to process data yourself:

### Option 1: Protomaps
```bash
# Sign up at https://protomaps.com (free tier)
# Download pre-made MBTiles for UAE region
```

### Option 2: Use Smaller Test Area

For testing, process just Dubai:

```bash
# Extract Dubai area using osmium
osmium extract -b 54.9,24.8,55.6,25.4 \
  united-arab-emirates-latest.osm.pbf \
  -o dubai.osm.pbf

# Then process dubai.osm.pbf instead
# Results in ~50-100MB total (much faster)
```

## Upload to GitHub Release

### Step 1: Create GitHub Repository

```bash
# Create repo on GitHub: your-username/uae-maps-data
git clone https://github.com/your-username/uae-maps-data.git
cd uae-maps-data
```

### Step 2: Create Release

1. Go to: `https://github.com/your-username/uae-maps-data/releases/new`
2. Tag version: `v1.0.0`
3. Release title: `UAE Maps Data v1.0.0`
4. Upload files:
   - `uae.mbtiles`
   - `valhalla_tiles.tar.gz`
   - `addresses.db`
   - `style.json`
5. Click "Publish release"

### Step 3: Update App Configuration

Edit `src/utils/constants.ts`:

```typescript
export const GITHUB_REPO = 'your-username/uae-maps-data';
export const GITHUB_RELEASE_TAG = 'v1.0.0';
```

## Verification

Test your files:

```bash
# Check MBTiles
sqlite3 uae.mbtiles "SELECT COUNT(*) FROM tiles;"

# Check Valhalla tiles
tar -tzf valhalla_tiles.tar.gz | head

# Check addresses database
sqlite3 addresses.db "SELECT COUNT(*) FROM addresses;"

# Check style JSON
cat style.json | python -m json.tool
```

## File Size Optimization

### Reduce MBTiles Size

```bash
# Limit zoom levels (reduce detail)
tilemaker --input united-arab-emirates-latest.osm.pbf \
          --output uae_compact.mbtiles \
          --zoom 10:18  # Only zoom levels 10-18

# Result: ~200-300MB (vs 400-700MB)
```

### Reduce Address Database

```sql
-- Remove less important POIs
DELETE FROM addresses WHERE type NOT IN ('street', 'building', 'address');
VACUUM;

-- Result: ~20-50MB (vs 50-200MB)
```

## Troubleshooting

### Docker Issues
```bash
# If permission denied
sudo docker run ...

# If out of memory
docker run --memory=4g ...
```

### Tilemaker Fails
```bash
# Use less threads
tilemaker --threads 2 ...

# Use smaller input area (Dubai only)
```

### Valhalla Build Fails
```bash
# Check config file syntax
cat valhalla.json | python -m json.tool

# Try with smaller OSM file
```

## Monthly Updates

Set up automated monthly updates:

```bash
#!/bin/bash
# update_maps.sh

# Download latest OSM data
wget -O uae-latest.osm.pbf https://download.geofabrik.de/asia/gcc-states/united-arab-emirates-latest.osm.pbf

# Process all files
./process_mbtiles.sh
./process_valhalla.sh
./process_addresses.sh

# Upload to new GitHub release
gh release create v$(date +%Y.%m.%d) \
  uae.mbtiles \
  valhalla_tiles.tar.gz \
  addresses.db \
  style.json
```

## Summary

1. **Download** UAE OSM data from Geofabrik
2. **Process** with Tilemaker → MBTiles
3. **Build** Valhalla routing tiles
4. **Extract** addresses to SQLite
5. **Download** map style JSON
6. **Upload** to GitHub Release
7. **Update** app constants with your repo
8. **Test** download in app

**Total time:** 2-4 hours (mostly automated)
**Total size:** ~800MB-1GB
**Cost:** $0 (all free open-source tools)
