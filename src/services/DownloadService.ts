import RNFS from 'react-native-fs';
import RNFetchBlob from 'rn-fetch-blob';
import {
  DATA_DIR,
  DOWNLOAD_URLS,
  MBTILES_PATH,
  VALHALLA_DIR,
  ADDRESSES_DB_PATH,
  STYLE_PATH,
  VERSION_FILE,
  GITHUB_RELEASE_TAG,
} from '../utils/constants';

export interface DownloadProgressCallback {
  (progress: {
    totalBytes: number;
    downloadedBytes: number;
    percentage: number;
    currentFile: string;
  }): void;
}

class DownloadService {
  private totalSize = 0;
  private downloadedSize = 0;

  async isDataDownloaded(): Promise<boolean> {
    try {
      const exists = await Promise.all([
        RNFS.exists(MBTILES_PATH),
        RNFS.exists(VALHALLA_DIR),
        RNFS.exists(ADDRESSES_DB_PATH),
        RNFS.exists(STYLE_PATH),
      ]);
      return exists.every(e => e);
    } catch (error) {
      console.error('Error checking data:', error);
      return false;
    }
  }

  async checkStorageSpace(): Promise<{hasSpace: boolean; available: number}> {
    try {
      const info = await RNFS.getFSInfo();
      const availableGB = info.freeSpace / (1024 * 1024 * 1024);
      const requiredGB = 1.2; // 1.2GB required
      return {
        hasSpace: availableGB >= requiredGB,
        available: availableGB,
      };
    } catch (error) {
      console.error('Error checking storage:', error);
      return {hasSpace: false, available: 0};
    }
  }

  async downloadAllData(
    onProgress: DownloadProgressCallback,
  ): Promise<boolean> {
    try {
      // Create data directory
      const dirExists = await RNFS.exists(DATA_DIR);
      if (!dirExists) {
        await RNFS.mkdir(DATA_DIR);
      }

      // Reset counters
      this.totalSize = 0;
      this.downloadedSize = 0;

      // Download files sequentially with progress
      const files = [
        {url: DOWNLOAD_URLS.STYLE, path: STYLE_PATH, name: 'Map Style'},
        {url: DOWNLOAD_URLS.ADDRESSES, path: ADDRESSES_DB_PATH, name: 'Address Database'},
        {url: DOWNLOAD_URLS.MBTILES, path: MBTILES_PATH, name: 'Map Tiles'},
        {url: DOWNLOAD_URLS.VALHALLA, path: `${DATA_DIR}/valhalla_tiles.tar.gz`, name: 'Routing Data'},
      ];

      for (const file of files) {
        const success = await this.downloadFile(file.url, file.path, file.name, onProgress);
        if (!success) {
          throw new Error(`Failed to download ${file.name}`);
        }
      }

      // Extract Valhalla tiles
      onProgress({
        totalBytes: this.totalSize,
        downloadedBytes: this.downloadedSize,
        percentage: 95,
        currentFile: 'Extracting routing data...',
      });

      await this.extractValhallaData();

      // Save version
      await RNFS.writeFile(VERSION_FILE, GITHUB_RELEASE_TAG, 'utf8');

      onProgress({
        totalBytes: this.totalSize,
        downloadedBytes: this.totalSize,
        percentage: 100,
        currentFile: 'Complete!',
      });

      return true;
    } catch (error) {
      console.error('Download error:', error);
      return false;
    }
  }

  private async downloadFile(
    url: string,
    path: string,
    name: string,
    onProgress: DownloadProgressCallback,
  ): Promise<boolean> {
    try {
      return await new Promise((resolve) => {
        RNFetchBlob.config({
          path: path,
          fileCache: true,
        })
          .fetch('GET', url, {})
          .progress((received, total) => {
            const fileProgress = received / total;
            const percentage = Math.floor(
              ((this.downloadedSize + received) / (this.totalSize || 1)) * 100,
            );
            
            onProgress({
              totalBytes: this.totalSize || total,
              downloadedBytes: this.downloadedSize + received,
              percentage: Math.min(percentage, 90),
              currentFile: `Downloading ${name}... ${Math.floor(fileProgress * 100)}%`,
            });
          })
          .then(res => {
            console.log('Downloaded:', res.path());
            const contentLength = res.info().headers?.['Content-Length'] || res.info().headers?.['content-length'] || 0;
            this.downloadedSize += Number(contentLength);
            this.totalSize = Math.max(this.totalSize, this.downloadedSize);
            resolve(true);
          })
          .catch(error => {
            console.error(`Download error for ${name}:`, error);
            resolve(false);
          });
      });
    } catch (error) {
      console.error('Download file error:', error);
      return false;
    }
  }

  private async extractValhallaData(): Promise<void> {
    try {
      const tarPath = `${DATA_DIR}/valhalla_tiles.tar.gz`;
      
      // Create valhalla directory
      const dirExists = await RNFS.exists(VALHALLA_DIR);
      if (!dirExists) {
        await RNFS.mkdir(VALHALLA_DIR);
      }

      // Note: For production, you'll need a native module or pre-extracted files
      // This is a placeholder - actual extraction needs native implementation
      console.log('Valhalla tiles should be pre-extracted or extracted via native module');
      
      // For now, we'll assume the tar.gz contains a flat directory structure
      // In production, upload pre-extracted files or implement native extraction
      
      // Delete tar file after extraction
      await RNFS.unlink(tarPath);
    } catch (error) {
      console.error('Extract error:', error);
      throw error;
    }
  }

  async checkForUpdates(): Promise<{
    hasUpdate: boolean;
    latestVersion: string;
  }> {
    try {
      const currentVersion = await this.getCurrentVersion();
      
      // Note: You'll need to implement version checking against GitHub API
      // For now, returning no update
      return {
        hasUpdate: false,
        latestVersion: currentVersion,
      };
    } catch (error) {
      console.error('Update check error:', error);
      return {hasUpdate: false, latestVersion: GITHUB_RELEASE_TAG};
    }
  }

  private async getCurrentVersion(): Promise<string> {
    try {
      const exists = await RNFS.exists(VERSION_FILE);
      if (exists) {
        return await RNFS.readFile(VERSION_FILE, 'utf8');
      }
      return '0.0.0';
    } catch (error) {
      return '0.0.0';
    }
  }

  async clearAllData(): Promise<void> {
    try {
      const exists = await RNFS.exists(DATA_DIR);
      if (exists) {
        await RNFS.unlink(DATA_DIR);
      }
    } catch (error) {
      console.error('Clear data error:', error);
    }
  }
}

export default new DownloadService();
