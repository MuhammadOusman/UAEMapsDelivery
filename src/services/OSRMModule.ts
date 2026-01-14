import { NativeModules } from 'react-native';

interface OSRMModuleInterface {
  initialize(dataPath: string): Promise<boolean>;
  route(from: { latitude: number; longitude: number }, to: { latitude: number; longitude: number }): Promise<{
    coordinates: number[][];
    distance: number;
    duration: number;
    instructions: Array<{
      text: string;
      distance: number;
      time: number;
      type: string;
    }>;
  }>;
  cleanup(): Promise<boolean>;
}

const { OSRMModule } = NativeModules;

export default OSRMModule as OSRMModuleInterface;
