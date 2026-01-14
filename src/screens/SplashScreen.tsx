import React, {useEffect, useState} from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  Image,
} from 'react-native';
import {NativeStackScreenProps} from '@react-navigation/native-stack';
import {RootStackParamList} from '../types';
import DownloadService from '../services/DownloadService';

type Props = NativeStackScreenProps<RootStackParamList, 'Splash'>;

const SplashScreen: React.FC<Props> = ({navigation}) => {
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    checkDataStatus();
  }, []);

  const checkDataStatus = async () => {
    try {
      const isDownloaded = await DownloadService.isDataDownloaded();
      
      setTimeout(() => {
        if (isDownloaded) {
          navigation.replace('Home');
        } else {
          navigation.replace('Download');
        }
      }, 2000);
    } catch (error) {
      console.error('Error checking data status:', error);
      navigation.replace('Download');
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>UAE Maps Delivery</Text>
        <Text style={styles.subtitle}>Offline Navigation for Riders</Text>
        <ActivityIndicator
          size="large"
          color="#007AFF"
          style={styles.loader}
        />
        <Text style={styles.status}>
          {checking ? 'Checking data...' : 'Loading...'}
        </Text>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    alignItems: 'center',
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginBottom: 40,
  },
  loader: {
    marginVertical: 20,
  },
  status: {
    fontSize: 14,
    color: '#999',
  },
});

export default SplashScreen;
