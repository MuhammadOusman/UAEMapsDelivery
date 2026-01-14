# UAE Maps Delivery App - Setup Summary (اردو/English)

## ✅ **App Ready Hai!**

Aapka app successfully build ho chuka hai aur emulator pe chal raha hai. Ab sirf **data processing** aur **GitHub upload** ki zaroorat hai.

---

## 📋 **Kya Karna Hai (Step by Step)**

### 1. **Docker Install Karein** (agar nahi hai)
- Download: https://www.docker.com/products/docker-desktop
- Install karein aur Docker Desktop start karein

### 2. **UAE Map Data Download Karein**
```powershell
# Yeh command PowerShell mein run karein
Invoke-WebRequest -Uri "https://download.geofabrik.de/asia/gcc-states/united-arab-emirates-latest.osm.pbf" -OutFile "united-arab-emirates-latest.osm.pbf"
```
Size: ~80-100MB | Time: 2-5 minutes

### 3. **Map Tiles Banayein (MBTiles)**
```powershell
# Docker se Tilemaker run karein
docker pull ghcr.io/systemed/tilemaker:latest

docker run -v ${PWD}:/data ghcr.io/systemed/tilemaker:latest /data/united-arab-emirates-latest.osm.pbf --output=/data/uae.mbtiles --process=/usr/local/share/tilemaker/resources/process-openmaptiles.lua --config=/usr/local/share/tilemaker/resources/config-openmaptiles.json
```
Output: `uae.mbtiles` (~400-700MB) | Time: 20-40 minutes

### 4. **OSRM Routing Data Banayein**
```powershell
# OSRM Docker image download
docker pull ghcr.io/project-osrm/osrm-backend:latest

# Step 1: Extract
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-extract -p /opt/car.lua /data/united-arab-emirates-latest.osm.pbf

# Step 2: Contract
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-contract /data/united-arab-emirates-latest.osrm

# Step 3: Partition
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-partition /data/united-arab-emirates-latest.osrm

# Step 4: Customize
docker run -t -v ${PWD}:/data ghcr.io/project-osrm/osrm-backend:latest osrm-customize /data/united-arab-emirates-latest.osrm

# Files rename karein
Rename-Item united-arab-emirates-latest.osrm uae.osrm
Rename-Item united-arab-emirates-latest.osrm.edges uae.osrm.edges
Rename-Item united-arab-emirates-latest.osrm.nodes uae.osrm.nodes
Rename-Item united-arab-emirates-latest.osrm.geometry uae.osrm.geometry
Rename-Item united-arab-emirates-latest.osrm.names uae.osrm.names
Rename-Item united-arab-emirates-latest.osrm.fileIndex uae.osrm.fileIndex
Rename-Item united-arab-emirates-latest.osrm.properties uae.osrm.properties
```
Output: 7 files (~200-400MB total) | Time: 15-30 minutes

### 5. **Address Database Banayein**

**Python script install karein:**
```powershell
pip install osmium
```

**Script create karein** (`extract_addresses.py`):
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
                center = w.nodes[len(w.nodes)//2]
                self.cursor.execute('''
                    INSERT INTO addresses (name, address, latitude, longitude, type)
                    VALUES (?, ?, ?, ?, ?)
                ''', (name, name, center.lat, center.lon, 'street'))

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

handler = AddressHandler(conn)
handler.apply_file('united-arab-emirates-latest.osm.pbf')

conn.commit()
conn.close()

print("Address database created: addresses.db")
```

**Run karein:**
```powershell
python extract_addresses.py
```
Output: `addresses.db` (~50-200MB) | Time: 5-10 minutes

### 6. **Map Style File**

**`style.json` create karein:**
```json
{
  "version": 8,
  "name": "UAE Basic",
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

## 📤 **GitHub Release Upload**

### Files Tayyar Hain:
1. ✅ `uae.mbtiles` (400-700MB)
2. ✅ `addresses.db` (50-200MB)
3. ✅ `style.json` (100KB)
4. ✅ `uae.osrm` (150-300MB)
5. ✅ `uae.osrm.edges`
6. ✅ `uae.osrm.nodes`
7. ✅ `uae.osrm.geometry`
8. ✅ `uae.osrm.names`
9. ✅ `uae.osrm.fileIndex`
10. ✅ `uae.osrm.properties`

### Upload Steps:
1. **GitHub pe jao:** https://github.com/MuhammadOusman/UAEMapsDelivery/releases/new
2. **Tag:** `v1.0.0`
3. **Title:** `UAE Maps Data v1.0.0`
4. **Description:** 
   ```
   Complete offline maps and routing data for UAE
   - Map tiles for display
   - OSRM routing engine files
   - Address search database
   - Total size: ~800MB-1.5GB
   ```
5. **Upload all 10 files**
6. **Publish Release** button dabayein

---

## 🚀 **App Test Karein**

```powershell
cd 'c:\Users\OUSMAN\Desktop\im cooked\Maps_proj\UAEMapsDelivery'
npm run android
```

### First Launch:
1. App download screen dikhayega
2. WiFi connect karein
3. Download start hoga (~800MB-1.5GB)
4. 5-15 minutes lagenge

### Testing:
1. ✅ Map tap karke pickup location set karein
2. ✅ Phir dropoff location set karein  
3. ✅ "Start Trip" button dabayein
4. ✅ OSRM se route calculate hoga (best quality!)
5. ✅ Turn-by-turn navigation shuru hoga
6. ✅ GPS tracking real-time chalega
7. ✅ "End Trip" button se khatam karein

---

## 📊 **File Sizes & Times**

| File | Size | Processing Time |
|------|------|----------------|
| uae.mbtiles | 400-700MB | 20-40 min |
| OSRM files | 200-400MB | 15-30 min |
| addresses.db | 50-200MB | 5-10 min |
| style.json | 100KB | 1 min |
| **Total** | **~800MB-1.5GB** | **~1-2 hours** |

---

## 🎯 **Production APK Build**

Jab testing complete ho jaye:

```powershell
cd android
.\gradlew assembleRelease
```

**APK location:**
```
android\app\build\outputs\apk\release\app-release.apk
```

Isko riders ko distribute kar sakte ho!

---

## ⚠️ **Important Notes**

1. **Docker zaroori hai** - Processing ke liye Docker Desktop running hona chahiye
2. **Storage check karein** - Kam se kam 10GB free space chahiye
3. **WiFi use karein** - Downloads ke liye stable internet
4. **Patience rakho** - First-time processing 1-2 hours lagta hai
5. **GitHub Release public rakho** - Warna app download nahi kar payega

---

## 🔧 **Troubleshooting**

### Download fail ho jaye:
```powershell
adb logcat | Select-String "DownloadService"
```

### Routing kaam na kare:
```powershell
adb logcat | Select-String "OSRM"
```

### Files check karein:
```powershell
adb shell ls -lh /data/user/0/com.uaemapsdelivery/files/map_data/
```

---

## 📞 **Help**

Detailed guide: `OSRM_SETUP.md` dekho project folder mein

**App Features:**
- ✅ Complete offline maps (no internet needed after download)
- ✅ OSRM routing (best quality, production-grade)
- ✅ Turn-by-turn navigation
- ✅ Real-time GPS tracking
- ✅ Location search
- ✅ Automatic re-routing
- ✅ Trip tracking
- ✅ Fast route calculation (<1 second)

**Technology:**
- React Native + TypeScript
- MapLibre GL (free, no API keys)
- OSRM native module (Java)
- SQLite address search
- OpenStreetMap data

---

## 🎉 **Done!**

Bas yeh steps complete karo aur aapka app fully functional ho jayega with **best-quality offline routing**! 🚀

Total time: **1-2 hours** (one-time setup)
