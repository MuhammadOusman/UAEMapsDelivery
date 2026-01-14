import NetInfo from '@react-native-community/netinfo';
import {UPDATE_CHECK_URL, GITHUB_RELEASE_TAG} from '../utils/constants';

interface UpdateInfo {
  hasUpdate: boolean;
  latestVersion: string;
  downloadUrl?: string;
  releaseNotes?: string;
}

class UpdateService {
  async checkForUpdates(): Promise<UpdateInfo> {
    try {
      // Check if connected to internet
      const netInfo = await NetInfo.fetch();
      if (!netInfo.isConnected) {
        return {
          hasUpdate: false,
          latestVersion: GITHUB_RELEASE_TAG,
        };
      }

      // Fetch latest release info from GitHub API
      const response = await fetch(UPDATE_CHECK_URL, {
        method: 'GET',
        headers: {
          Accept: 'application/vnd.github.v3+json',
        },
      });

      if (!response.ok) {
        throw new Error('Failed to fetch update info');
      }

      const releaseData = await response.json();
      const latestVersion = releaseData.tag_name;

      // Compare versions
      const hasUpdate = this.compareVersions(latestVersion, GITHUB_RELEASE_TAG);

      return {
        hasUpdate,
        latestVersion,
        downloadUrl: releaseData.html_url,
        releaseNotes: releaseData.body,
      };
    } catch (error) {
      console.error('Update check error:', error);
      return {
        hasUpdate: false,
        latestVersion: GITHUB_RELEASE_TAG,
      };
    }
  }

  private compareVersions(latest: string, current: string): boolean {
    // Remove 'v' prefix if present
    const latestClean = latest.replace(/^v/, '');
    const currentClean = current.replace(/^v/, '');

    // Split into parts
    const latestParts = latestClean.split('.').map(Number);
    const currentParts = currentClean.split('.').map(Number);

    // Compare major, minor, patch
    for (let i = 0; i < 3; i++) {
      const latestPart = latestParts[i] || 0;
      const currentPart = currentParts[i] || 0;

      if (latestPart > currentPart) {
        return true; // Update available
      } else if (latestPart < currentPart) {
        return false; // Current is newer (shouldn't happen in production)
      }
    }

    return false; // Versions are equal
  }

  async shouldCheckForUpdates(lastCheckTime: number): Promise<boolean> {
    // Check once per week (7 days)
    const ONE_WEEK = 7 * 24 * 60 * 60 * 1000;
    const now = Date.now();
    return now - lastCheckTime > ONE_WEEK;
  }
}

export default new UpdateService();
