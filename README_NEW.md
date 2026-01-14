# UAE Maps Delivery App

**Offline navigation for delivery riders in the UAE** - No paid APIs required!

A React Native mobile application that provides **complete offline maps** and **turn-by-turn navigation** for delivery riders in the United Arab Emirates. Built with OpenStreetMap data, MapLibre GL, and Valhalla routing engine.

## 🎯 Features

- ✅ **100% Offline Maps** - Complete UAE map tiles with street-level detail
- ✅ **Offline Navigation** - Turn-by-turn directions without internet
- ✅ **Location Search** - Search addresses, streets, and landmarks
- ✅ **Simple Trip Management** - Pickup → Navigate → Dropoff → Complete
- ✅ **Real-time GPS Tracking** - Follow delivery route with live position
- ✅ **Auto Re-routing** - Recalculates route when driver deviates
- ✅ **WiFi-Only Downloads** - ~800MB-1GB initial data download
- ✅ **Background Updates** - Monthly map data updates
- ✅ **Free & Open Source** - No API costs, no subscriptions

## 🚀 Quick Start

### Prerequisites

1. **React Native Development Environment**
   - Node.js 18+
   - React Native CLI
   - Android Studio (for Android) or Xcode (for iOS)
   - See: https://reactnative.dev/docs/environment-setup

2. **Map Data Files** (See [SETUP.md](./SETUP.md))
   - You need to process and host map data on GitHub Releases
   - Or use test/mock data for development

### Installation

```bash
# Install dependencies
npm install

# iOS only: Install CocoaPods
cd ios && pod install && cd ..

# Update constants with your GitHub repo
# Edit: src/utils/constants.ts
```

### Configuration

**IMPORTANT:** Before running, update `src/utils/constants.ts`:

```typescript
export const GITHUB_REPO = 'YOUR_USERNAME/YOUR_REPO';
export const GITHUB_RELEASE_TAG = 'v1.0.0';
```

See **[SETUP.md](./SETUP.md)** for detailed configuration instructions.

### Run the App

```bash
# Android
npm run android

# iOS
npm run ios
```

## 📚 Documentation

- **[SETUP.md](./SETUP.md)** - Complete setup and configuration guide
- **[DATA_PROCESSING.md](./DATA_PROCESSING.md)** - How to process map data from OpenStreetMap

## 🗺️ How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│         React Native App                │
├─────────────────────────────────────────┤
│  🎨 UI Layer                            │
│    - Location search                    │
│    - Trip management                    │
│    - Navigation display                 │
├─────────────────────────────────────────┤
│  🗺️ Map Rendering (MapLibre GL)        │
│    - Offline vector tiles (MBTiles)     │
│    - Custom styling                     │
│    - Markers and routes                 │
├─────────────────────────────────────────┤
│  🧭 Routing Engine (Valhalla)          │
│    - Offline route calculation          │
│    - Turn-by-turn instructions          │
│    - Auto re-routing                    │
├─────────────────────────────────────────┤
│  💾 Data Storage                        │
│    - SQLite address database            │
│    - Offline map tiles                  │
│    - Routing graph                      │
└─────────────────────────────────────────┘
```

### Data Sources

- **Maps:** OpenStreetMap (via Geofabrik)
- **Tiles:** MBTiles format (vector tiles)
- **Routing:** Valhalla routing engine
- **Addresses:** Extracted from OSM data
- **Hosting:** GitHub Releases (free)

## 📦 What You Need to Provide

To make the app fully functional, you need to:

1. **Create a GitHub repository** for map data hosting
2. **Process UAE map data** into required formats:
   - `uae.mbtiles` (~400-700MB) - Map tiles
   - `valhalla_tiles.tar.gz` (~50-100MB) - Routing data
   - `addresses.db` (~50-200MB) - Location search database
   - `style.json` (~50KB) - Map styling
3. **Upload files** to GitHub Release
4. **Update app configuration** with your repo details

See **[DATA_PROCESSING.md](./DATA_PROCESSING.md)** for step-by-step instructions.

## 🛠️ Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | React Native 0.83+ |
| Language | TypeScript |
| Maps | MapLibre GL Native |
| Routing | Valhalla (offline) |
| Data Source | OpenStreetMap |
| Tile Format | MBTiles (vector) |
| Database | SQLite |
| Navigation | React Navigation |
| Location | React Native Geolocation |
| Downloads | RN Fetch Blob |
| Hosting | GitHub Releases |

## 🔧 Development

### Project Structure

```
UAEMapsDelivery/
├── src/
│   ├── screens/          # App screens
│   │   ├── SplashScreen.tsx
│   │   ├── DownloadScreen.tsx
│   │   ├── HomeScreen.tsx
│   │   └── NavigationScreen.tsx
│   ├── services/         # Business logic
│   │   ├── DownloadService.ts
│   │   ├── LocationSearchService.ts
│   │   ├── RoutingService.ts
│   │   └── UpdateService.ts
│   ├── navigation/       # Navigation setup
│   ├── components/       # Reusable components
│   ├── utils/           # Constants and helpers
│   └── types/           # TypeScript types
├── android/             # Android native code
├── ios/                 # iOS native code
└── package.json
```

## 🚧 Current Status

### ✅ Implemented
- Complete app structure and navigation
- Download manager with progress tracking
- Location search with SQLite
- Map display with MapLibre GL
- Turn-by-turn navigation UI
- GPS tracking and route following
- Auto re-routing on deviation
- Update checker

### ⚠️ Needs Configuration
- **GitHub repository** for map data hosting
- **Map data files** processed and uploaded
- **Valhalla native integration** (currently mock)
- **iOS/Android permissions** testing

### 🎯 Optional Enhancements
- Voice navigation
- Offline speech synthesis
- Trip history and analytics
- Multi-stop deliveries
- Battery optimization
- Dark mode

## 📊 Performance

- **App Size:** ~30MB (without data)
- **Data Download:** ~800MB-1GB (one-time)
- **RAM Usage:** ~150-300MB during navigation
- **Battery:** Optimized for delivery use (GPS + screen)
- **Route Calculation:** 1-5 seconds for typical UAE distances

## 📄 License

This project is open source. Map data from OpenStreetMap is © OpenStreetMap contributors.

## 🙏 Acknowledgments

- **OpenStreetMap** - Map data
- **Geofabrik** - OSM data extracts
- **MapLibre** - Open-source maps library
- **Valhalla** - Routing engine
- **React Native** - Mobile framework

---

**Built for delivery riders, by developers who care about offline-first apps.** 🚚📦
