import React from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {RootStackParamList} from '../types';
import SplashScreen from '../screens/SplashScreen';
import DownloadScreen from '../screens/DownloadScreen';
import HomeScreen from '../screens/HomeScreen';
import NavigationScreen from '../screens/NavigationScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

const AppNavigator: React.FC = () => {
  return (
    <NavigationContainer>
      <Stack.Navigator
        initialRouteName="Splash"
        screenOptions={{
          headerShown: false,
        }}>
        <Stack.Screen name="Splash" component={SplashScreen} />
        <Stack.Screen name="Download" component={DownloadScreen} />
        <Stack.Screen
          name="Home"
          component={HomeScreen}
          options={{headerShown: true, title: 'Select Locations'}}
        />
        <Stack.Screen
          name="Navigation"
          component={NavigationScreen}
          options={{
            headerShown: true,
            title: 'Navigation',
            headerBackVisible: false,
          }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
};

export default AppNavigator;
