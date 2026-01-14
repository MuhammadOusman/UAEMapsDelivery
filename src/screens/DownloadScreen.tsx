import React, {useState, useEffect} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
} from 'react-native';
import {NativeStackScreenProps} from '@react-navigation/native-stack';
import NetInfo from '@react-native-community/netinfo';
import {RootStackParamList} from '../types';
import DownloadService from '../services/DownloadService';

type Props = NativeStackScreenProps<RootStackParamList, 'Download'>;

const DownloadScreen: React.FC<Props> = ({navigation}) => {
  const [downloading, setDownloading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [currentFile, setCurrentFile] = useState('');
  const [downloadedMB, setDownloadedMB] = useState(0);
  const [totalMB, setTotalMB] = useState(0);
  const [isWifi, setIsWifi] = useState(false);
  const [hasSpace, setHasSpace] = useState(true);
  const [availableSpace, setAvailableSpace] = useState(0);

  useEffect(() => {
    checkConnectivity();
    checkStorage();
  }, []);

  const checkConnectivity = async () => {
    const state = await NetInfo.fetch();
    setIsWifi(state.type === 'wifi');
  };

  const checkStorage = async () => {
    const storage = await DownloadService.checkStorageSpace();
    setHasSpace(storage.hasSpace);
    setAvailableSpace(storage.available);
  };

  const startDownload = async () => {
    if (!isWifi) {
      Alert.alert(
        'WiFi Required',
        'Please connect to WiFi to download map data (~800MB-1GB)',
        [{text: 'OK'}],
      );
      return;
    }

    if (!hasSpace) {
      Alert.alert(
        'Insufficient Storage',
        `You need at least 1.2GB of free space. Available: ${availableSpace.toFixed(2)}GB`,
        [{text: 'OK'}],
      );
      return;
    }

    setDownloading(true);

    const success = await DownloadService.downloadAllData(progressData => {
      setProgress(progressData.percentage);
      setCurrentFile(progressData.currentFile);
      setDownloadedMB(progressData.downloadedBytes / (1024 * 1024));
      setTotalMB(progressData.totalBytes / (1024 * 1024));
    });

    if (success) {
      Alert.alert('Success', 'Map data downloaded successfully!', [
        {
          text: 'OK',
          onPress: () => navigation.replace('Home'),
        },
      ]);
    } else {
      Alert.alert(
        'Download Failed',
        'Failed to download map data. Please check your connection and try again.',
        [{text: 'OK', onPress: () => setDownloading(false)}],
      );
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>Download Map Data</Text>
        <Text style={styles.description}>
          This app requires offline map data for UAE to function.
        </Text>

        <View style={styles.infoBox}>
          <InfoRow label="Download Size" value="~800MB - 1GB" />
          <InfoRow
            label="WiFi Connection"
            value={isWifi ? '✓ Connected' : '✗ Not connected'}
            valueColor={isWifi ? '#4CAF50' : '#F44336'}
          />
          <InfoRow
            label="Available Space"
            value={`${availableSpace.toFixed(2)}GB`}
            valueColor={hasSpace ? '#4CAF50' : '#F44336'}
          />
        </View>

        {downloading ? (
          <View style={styles.progressContainer}>
            <Text style={styles.progressText}>
              {currentFile || 'Downloading...'}
            </Text>
            <View style={styles.progressBar}>
              <View style={[styles.progressFill, {width: `${progress}%`}]} />
            </View>
            <Text style={styles.progressPercentage}>{progress}%</Text>
            {totalMB > 0 && (
              <Text style={styles.progressSize}>
                {downloadedMB.toFixed(1)} MB / {totalMB.toFixed(1)} MB
              </Text>
            )}
            <ActivityIndicator
              size="large"
              color="#007AFF"
              style={styles.loader}
            />
          </View>
        ) : (
          <TouchableOpacity
            style={[
              styles.downloadButton,
              (!isWifi || !hasSpace) && styles.downloadButtonDisabled,
            ]}
            onPress={startDownload}
            disabled={!isWifi || !hasSpace}>
            <Text style={styles.downloadButtonText}>Download Now</Text>
          </TouchableOpacity>
        )}

        {!isWifi && (
          <Text style={styles.warningText}>
            ⚠️ Please connect to WiFi to download
          </Text>
        )}
        {!hasSpace && (
          <Text style={styles.warningText}>
            ⚠️ Insufficient storage space
          </Text>
        )}
      </View>
    </View>
  );
};

const InfoRow: React.FC<{
  label: string;
  value: string;
  valueColor?: string;
}> = ({label, value, valueColor = '#333'}) => (
  <View style={styles.infoRow}>
    <Text style={styles.infoLabel}>{label}:</Text>
    <Text style={[styles.infoValue, {color: valueColor}]}>{value}</Text>
  </View>
);

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  content: {
    flex: 1,
    padding: 20,
    justifyContent: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 12,
    textAlign: 'center',
  },
  description: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 30,
    lineHeight: 22,
  },
  infoBox: {
    backgroundColor: '#F5F5F5',
    borderRadius: 12,
    padding: 16,
    marginBottom: 30,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
  },
  infoLabel: {
    fontSize: 14,
    color: '#666',
    fontWeight: '500',
  },
  infoValue: {
    fontSize: 14,
    fontWeight: 'bold',
  },
  downloadButton: {
    backgroundColor: '#007AFF',
    paddingVertical: 16,
    paddingHorizontal: 32,
    borderRadius: 12,
    alignItems: 'center',
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.2,
    shadowRadius: 4,
  },
  downloadButtonDisabled: {
    backgroundColor: '#CCC',
  },
  downloadButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
  progressContainer: {
    alignItems: 'center',
  },
  progressText: {
    fontSize: 14,
    color: '#666',
    marginBottom: 12,
    textAlign: 'center',
  },
  progressBar: {
    width: '100%',
    height: 8,
    backgroundColor: '#E0E0E0',
    borderRadius: 4,
    overflow: 'hidden',
    marginBottom: 8,
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#007AFF',
  },
  progressPercentage: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#007AFF',
    marginBottom: 4,
  },
  progressSize: {
    fontSize: 12,
    color: '#999',
  },
  loader: {
    marginTop: 20,
  },
  warningText: {
    fontSize: 14,
    color: '#F44336',
    textAlign: 'center',
    marginTop: 16,
  },
});

export default DownloadScreen;
