// Minimal stub API surface for HERE SDK used by the app.

class OfflineRegionInfo {
  final String id;
  final int sizeBytes;
  OfflineRegionInfo(this.id, this.sizeBytes);
}

typedef ProgressCallback = void Function(int bytesDownloaded, int totalBytes);

class OfflineManager {
  // simulate available region
  List<OfflineRegionInfo> getAvailableRegions() => [OfflineRegionInfo('UAE', 400 * 1024 * 1024)];

  Future<void> downloadRegion(String id, {required ProgressCallback onProgress}) async {
    // Simulate download progress for development; replace with real download calls when HERE SDK is installed.
    final total = 400 * 1024 * 1024;
    var done = 0;
    while (done < total) {
      await Future.delayed(const Duration(milliseconds: 200));
      done += 2 * 1024 * 1024; // 2MB increments
      if (done > total) done = total;
      onProgress(done, total);
    }
  }

  Future<bool> isRegionDownloaded(String id) async {
    // Development stub: always false
    return false;
  }
}

// Export a singleton manager
final OfflineManager offlineManager = OfflineManager();
