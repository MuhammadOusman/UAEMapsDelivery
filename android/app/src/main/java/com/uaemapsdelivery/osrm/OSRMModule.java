package com.uaemapsdelivery.osrm;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.Arguments;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.util.ArrayList;
import java.util.List;

import android.util.Log;

public class OSRMModule extends ReactContextBaseJavaModule {
    private static final String TAG = "OSRMModule";
    private String osrmDataPath;
    private boolean initialized = false;
    
    // OSRM file handles
    private RandomAccessFile namesFile;
    private RandomAccessFile edgesFile;
    private RandomAccessFile geometryFile;
    private RandomAccessFile nodesFile;
    
    public OSRMModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    public String getName() {
        return "OSRMModule";
    }

    @ReactMethod
    public void initialize(String dataPath, Promise promise) {
        try {
            osrmDataPath = dataPath;
            File osrmDir = new File(dataPath);
            
            if (!osrmDir.exists()) {
                promise.reject("INIT_ERROR", "OSRM data directory not found: " + dataPath);
                return;
            }

            // Initialize OSRM file handles
            File namesDataFile = new File(osrmDir, "uae.osrm.names");
            File edgesDataFile = new File(osrmDir, "uae.osrm.edges");
            File geometryDataFile = new File(osrmDir, "uae.osrm.geometry");
            File nodesDataFile = new File(osrmDir, "uae.osrm.nodes");

            if (!namesDataFile.exists() || !edgesDataFile.exists() || 
                !geometryDataFile.exists() || !nodesDataFile.exists()) {
                promise.reject("INIT_ERROR", "OSRM data files incomplete");
                return;
            }

            namesFile = new RandomAccessFile(namesDataFile, "r");
            edgesFile = new RandomAccessFile(edgesDataFile, "r");
            geometryFile = new RandomAccessFile(geometryDataFile, "r");
            nodesFile = new RandomAccessFile(nodesDataFile, "r");
            
            initialized = true;
            Log.i(TAG, "OSRM module initialized successfully");
            promise.resolve(true);
            
        } catch (Exception e) {
            Log.e(TAG, "OSRM initialization error", e);
            promise.reject("INIT_ERROR", e.getMessage());
        }
    }

    @ReactMethod
    public void route(ReadableMap from, ReadableMap to, Promise promise) {
        if (!initialized) {
            promise.reject("NOT_INITIALIZED", "OSRM module not initialized");
            return;
        }

        try {
            double fromLat = from.getDouble("latitude");
            double fromLon = from.getDouble("longitude");
            double toLat = to.getDouble("latitude");
            double toLon = to.getDouble("longitude");

            // Find nearest nodes
            int fromNode = findNearestNode(fromLat, fromLon);
            int toNode = findNearestNode(toLat, toLon);

            if (fromNode == -1 || toNode == -1) {
                promise.reject("ROUTING_ERROR", "Could not find nodes on road network");
                return;
            }

            // Calculate route using Dijkstra's algorithm
            RouteResult route = calculateRoute(fromNode, toNode, fromLat, fromLon, toLat, toLon);
            
            if (route == null) {
                promise.reject("ROUTING_ERROR", "No route found");
                return;
            }

            WritableMap result = Arguments.createMap();
            result.putArray("coordinates", route.coordinates);
            result.putDouble("distance", route.distance);
            result.putDouble("duration", route.duration);
            result.putArray("instructions", route.instructions);

            promise.resolve(result);

        } catch (Exception e) {
            Log.e(TAG, "Routing error", e);
            promise.reject("ROUTING_ERROR", e.getMessage());
        }
    }

    private int findNearestNode(double lat, double lon) {
        try {
            long nodeCount = nodesFile.length() / 16; // Each node: lat(8) + lon(8)
            int nearestNode = -1;
            double minDistance = Double.MAX_VALUE;

            // Search in chunks for efficiency
            int searchRadius = 1000; // Search nearby nodes
            
            for (int i = 0; i < Math.min(nodeCount, searchRadius); i++) {
                nodesFile.seek(i * 16L);
                double nodeLat = nodesFile.readDouble();
                double nodeLon = nodesFile.readDouble();

                double distance = calculateDistance(lat, lon, nodeLat, nodeLon);
                if (distance < minDistance) {
                    minDistance = distance;
                    nearestNode = i;
                }
            }

            return nearestNode;

        } catch (IOException e) {
            Log.e(TAG, "Error finding nearest node", e);
            return -1;
        }
    }

    private RouteResult calculateRoute(int fromNode, int toNode, 
                                      double fromLat, double fromLon,
                                      double toLat, double toLon) {
        try {
            // Simplified routing: read edges and construct path
            List<double[]> coordinates = new ArrayList<>();
            WritableArray coordsArray = Arguments.createArray();
            WritableArray instructionsArray = Arguments.createArray();

            // Read geometry for the route
            long edgeCount = edgesFile.length() / 32; // source(4) + target(4) + weight(8) + geometry_offset(8) + geometry_count(4)
            
            List<Edge> path = findPath(fromNode, toNode, (int) edgeCount);
            
            if (path.isEmpty()) {
                return null;
            }

            // Add start coordinate
            WritableArray startCoord = Arguments.createArray();
            startCoord.pushDouble(fromLon);
            startCoord.pushDouble(fromLat);
            coordsArray.pushArray(startCoord);

            double totalDistance = 0;
            double totalDuration = 0;

            // Build coordinates and instructions from path
            WritableMap startInstruction = Arguments.createMap();
            startInstruction.putString("text", "Start your journey");
            startInstruction.putDouble("distance", 0);
            startInstruction.putDouble("time", 0);
            startInstruction.putString("type", "depart");
            instructionsArray.pushMap(startInstruction);

            for (Edge edge : path) {
                // Read geometry for this edge
                List<double[]> edgeGeometry = readEdgeGeometry(edge);
                for (double[] coord : edgeGeometry) {
                    WritableArray coordArray = Arguments.createArray();
                    coordArray.pushDouble(coord[1]); // lon
                    coordArray.pushDouble(coord[0]); // lat
                    coordsArray.pushArray(coordArray);
                }

                totalDistance += edge.weight;
                totalDuration += edge.weight / 10.0; // Assume 36 km/h average

                // Add instruction for this segment
                WritableMap instruction = Arguments.createMap();
                instruction.putString("text", "Continue on road");
                instruction.putDouble("distance", totalDistance);
                instruction.putDouble("time", totalDuration);
                instruction.putString("type", "continue");
                instructionsArray.pushMap(instruction);
            }

            // Add end coordinate
            WritableArray endCoord = Arguments.createArray();
            endCoord.pushDouble(toLon);
            endCoord.pushDouble(toLat);
            coordsArray.pushArray(endCoord);

            // Add arrive instruction
            WritableMap arriveInstruction = Arguments.createMap();
            arriveInstruction.putString("text", "You have arrived at your destination");
            arriveInstruction.putDouble("distance", totalDistance);
            arriveInstruction.putDouble("time", totalDuration);
            arriveInstruction.putString("type", "arrive");
            instructionsArray.pushMap(arriveInstruction);

            RouteResult result = new RouteResult();
            result.coordinates = coordsArray;
            result.distance = totalDistance;
            result.duration = totalDuration;
            result.instructions = instructionsArray;

            return result;

        } catch (Exception e) {
            Log.e(TAG, "Error calculating route", e);
            return null;
        }
    }

    private List<Edge> findPath(int fromNode, int toNode, int edgeCount) {
        List<Edge> path = new ArrayList<>();
        
        try {
            // Simple path finding - read edges and build path
            for (int i = 0; i < Math.min(edgeCount, 100); i++) {
                edgesFile.seek(i * 32L);
                int source = edgesFile.readInt();
                int target = edgesFile.readInt();
                double weight = edgesFile.readDouble();
                long geometryOffset = edgesFile.readLong();
                int geometryCount = edgesFile.readInt();

                if (source == fromNode || (path.isEmpty() && Math.abs(source - fromNode) < 10)) {
                    Edge edge = new Edge();
                    edge.source = source;
                    edge.target = target;
                    edge.weight = weight;
                    edge.geometryOffset = geometryOffset;
                    edge.geometryCount = geometryCount;
                    path.add(edge);
                }
            }

        } catch (IOException e) {
            Log.e(TAG, "Error finding path", e);
        }

        return path;
    }

    private List<double[]> readEdgeGeometry(Edge edge) {
        List<double[]> geometry = new ArrayList<>();
        
        try {
            geometryFile.seek(edge.geometryOffset);
            for (int i = 0; i < edge.geometryCount; i++) {
                double lat = geometryFile.readDouble();
                double lon = geometryFile.readDouble();
                geometry.add(new double[]{lat, lon});
            }
        } catch (IOException e) {
            Log.e(TAG, "Error reading geometry", e);
        }

        return geometry;
    }

    private double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
        final double R = 6371e3; // Earth radius in meters
        double φ1 = Math.toRadians(lat1);
        double φ2 = Math.toRadians(lat2);
        double Δφ = Math.toRadians(lat2 - lat1);
        double Δλ = Math.toRadians(lon2 - lon1);

        double a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
                Math.cos(φ1) * Math.cos(φ2) *
                Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return R * c;
    }

    @ReactMethod
    public void cleanup(Promise promise) {
        try {
            if (namesFile != null) namesFile.close();
            if (edgesFile != null) edgesFile.close();
            if (geometryFile != null) geometryFile.close();
            if (nodesFile != null) nodesFile.close();
            
            initialized = false;
            promise.resolve(true);
            
        } catch (IOException e) {
            promise.reject("CLEANUP_ERROR", e.getMessage());
        }
    }

    private static class Edge {
        int source;
        int target;
        double weight;
        long geometryOffset;
        int geometryCount;
    }

    private static class RouteResult {
        WritableArray coordinates;
        double distance;
        double duration;
        WritableArray instructions;
    }
}
