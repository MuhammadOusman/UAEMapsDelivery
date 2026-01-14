# ⚡ Quick Reference Guide

## 🚀 Run the App (Right Now)

```bash
cd UAEMapsDelivery
npm install
npm run android  # or npm run ios
```

**Status:** Works immediately with mock data for UI testing

---

## 🔧 Configure for Production

### 1. Update Constants (5 minutes)

Edit: `src/utils/constants.ts`

```typescript
// Change these two lines:
export const GITHUB_REPO = 'your-username/your-repo-name';
export const GITHUB_RELEASE_TAG = 'v1.0.0';
```

### 2. Process Map Data (3-5 hours - one time)

See detailed guide: `DATA_PROCESSING.md`

**Quick Docker Commands:**

```bash
# Download UAE OSM data
wget https://download.geofabrik.de/asia/gcc-states/united-arab-emirates-latest.osm.pbf

# Generate map tiles
docker run -v $(pwd):/data ghcr.io/systemed/tilemaker:latest \
  /data/united-arab-emirates-latest.osm.pbf \
  --output=/data/uae.mbtiles

# Build routing tiles  
docker run -v $(pwd):/data ghcr.io/valhalla/valhalla:latest \
  valhalla_build_tiles -c /data/valhalla.json \
  /data/united-arab-emirates-latest.osm.pbf

# Extract addresses (use provided Python script)
python extract_addresses.py united-arab-emirates-latest.osm.pbf addresses.db

# Download style
wget https://raw.githubusercontent.com/openmaptiles/osm-bright-gl-style/master/style.json
```

### 3. Upload to GitHub (10 minutes)

1. Create repo: `your-username/uae-maps-data`
2. Go to: Releases → New Release
3. Tag: `v1.0.0`
4. Upload files:
   - `uae.mbtiles` (~400-700MB)
   - `valhalla_tiles.tar.gz` (~50-100MB)
   - `addresses.db` (~50-200MB)
   - `style.json` (~50KB)
5. Publish release

---

## 📱 App Structure

```
src/
├── screens/
│   ├── SplashScreen.tsx      → Initial loading
│   ├── DownloadScreen.tsx    → Downloads map data
│   ├── HomeScreen.tsx         → Search & select locations
│   └── NavigationScreen.tsx  → Turn-by-turn navigation
│
├── services/
│   ├── DownloadService.ts         → Handles downloads
│   ├── LocationSearchService.ts   → SQLite search
│   ├── RoutingService.ts          → Valhalla routing
│   └── UpdateService.ts           → Check for updates
│
├── utils/
│   └── constants.ts          → ⚠️ UPDATE THIS FILE
│
└── types/
    └── index.ts              → TypeScript interfaces
```

---

## 🔑 Key Files to Know

| File | What It Does | Action Needed |
|------|-------------|---------------|
| `src/utils/constants.ts` | GitHub URLs, config | ✏️ EDIT THIS |
| `src/services/RoutingService.ts` | Route calculation | 🟡 Mock for now |
| `DATA_PROCESSING.md` | Map data guide | 📖 READ THIS |
| `SETUP.md` | Full setup guide | 📖 READ THIS |
| `WHAT_YOU_NEED.md` | Requirements | 📖 READ THIS |

---

## 🧪 Testing Checklist

### Without Real Data (Now)
- [ ] App launches
- [ ] Splash screen shows
- [ ] Download screen displays
- [ ] Can navigate to Home screen
- [ ] Location buttons work
- [ ] Can select pickup/dropoff (tap map)
- [ ] Start trip button appears
- [ ] Navigation screen opens
- [ ] End trip works

### With Real Data (After Setup)
- [ ] Download screen detects WiFi
- [ ] Downloads files with progress
- [ ] Map displays with UAE tiles
- [ ] Can search locations
- [ ] Search returns results
- [ ] Selected location shows on map
- [ ] Route calculates between points
- [ ] Route displays on map
- [ ] GPS tracking works
- [ ] Turn-by-turn instructions show
- [ ] Re-routing works when off-route

---

## 🐛 Common Issues

### Issue: "Failed to download"
**Solution:** Check `constants.ts` has correct GitHub URLs

### Issue: "Map not displaying"
**Solution:** Ensure `uae.mbtiles` was downloaded correctly

### Issue: "Search returns nothing"
**Solution:** Check `addresses.db` exists and has data

### Issue: "Routing shows straight line"
**Solution:** This is normal - using mock routing. See `WHAT_YOU_NEED.md` for Valhalla integration

### Issue: "App crashes on Android"
**Solution:** Check permissions in `AndroidManifest.xml` are correct

### Issue: "Location not working on iOS"
**Solution:** Check `Info.plist` has location permission descriptions

---

## 📊 App Flow

```
Splash → Check data exists?
            ↓ No
         Download → WiFi check → Download files → Extract
            ↓ Yes
         Home → Search pickup → Search dropoff → Start Trip
            ↓
         Navigation → GPS tracking → Turn-by-turn → End Trip
            ↓
         Home (repeat)
```

---

## 🎯 Priority Tasks

### High Priority (Must Do)
1. ✅ Run app to test UI (0 min - already works)
2. ❗ Create GitHub repo (5 min)
3. ❗ Process map data (3-5 hours)
4. ❗ Update constants.ts (5 min)

### Medium Priority (Should Do)
5. 🟡 Test on real device with GPS
6. 🟡 Implement Valhalla native module
7. 🟡 Test offline mode completely

### Low Priority (Nice to Have)
8. 🟢 Voice navigation
9. 🟢 Trip history
10. 🟢 Dark mode

---

## 📞 Need Help?

1. **Check guides:**
   - `SETUP.md` - Complete setup
   - `DATA_PROCESSING.md` - Process map data
   - `WHAT_YOU_NEED.md` - Requirements

2. **Common resources:**
   - Tilemaker: https://github.com/systemed/tilemaker
   - Valhalla: https://github.com/valhalla/valhalla
   - MapLibre: https://maplibre.org
   - OSM Data: https://download.geofabrik.de

3. **Communities:**
   - r/openstreetmap
   - MapLibre Slack
   - React Native Discord

---

## ⚡ Quick Commands

```bash
# Install dependencies
npm install

# Run Android
npm run android

# Run iOS
npm run ios

# Clean build (if issues)
cd android && ./gradlew clean && cd ..
npm start -- --reset-cache

# Check for errors
npm run lint

# Format code
npm run format
```

---

## 📦 File Sizes

| File | Size | Required |
|------|------|----------|
| `uae.mbtiles` | ~400-700MB | ✅ Yes |
| `valhalla_tiles.tar.gz` | ~50-100MB | ✅ Yes |
| `addresses.db` | ~50-200MB | ✅ Yes |
| `style.json` | ~50KB | ✅ Yes |
| **Total Download** | **~800MB-1GB** | One-time |

---

## 🎓 Learning Resources

- **OpenStreetMap:** https://learnosm.org
- **React Native:** https://reactnative.dev/docs/getting-started
- **TypeScript:** https://www.typescriptlang.org/docs
- **MapLibre GL:** https://maplibre.org/maplibre-gl-js-docs
- **Valhalla:** https://valhalla.readthedocs.io

---

## ✨ Pro Tips

1. **Start small:** Test with Dubai area only first (faster processing)
2. **Use Docker:** Easier than installing all tools locally
3. **Test incrementally:** Test each screen as you build
4. **Mock data first:** Build UI before processing real data
5. **Version your data:** Use semantic versioning for releases (v1.0.0, v1.1.0, etc.)
6. **Automate updates:** Set up cron job for monthly data updates
7. **Compress well:** Use `tar -czf` for Valhalla tiles
8. **Index properly:** Add SQLite indexes for fast searches
9. **Test offline:** Turn off WiFi to verify true offline mode
10. **Battery test:** Check battery usage during long navigation

---

**You're all set! Start with running the app, then process data when ready.** 🚀
