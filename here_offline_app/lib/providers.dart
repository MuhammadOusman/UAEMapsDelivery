import 'package:flutter/material.dart';
import 'package:here_sdk/core.dart';
import 'package:riverpod/riverpod.dart';

// Delivery State Provider
final deliveryStateProvider = StateNotifierProvider<DeliveryNotifier, DeliveryState>((ref) {
  return DeliveryNotifier();
});

class DeliveryState {
  final String customerName;
  final GeoCoordinates? pickupCoords;
  final GeoCoordinates? dropCoords;
  final String pickupAddress;
  final String dropAddress;
  final bool pickedUp;
  final double distanceTravelled;

  DeliveryState({
    this.customerName = '',
    this.pickupCoords,
    this.dropCoords,
    this.pickupAddress = '',
    this.dropAddress = '',
    this.pickedUp = false,
    this.distanceTravelled = 0.0,
  });

  DeliveryState copyWith({
    String? customerName,
    GeoCoordinates? pickupCoords,
    GeoCoordinates? dropCoords,
    String? pickupAddress,
    String? dropAddress,
    bool? pickedUp,
    double? distanceTravelled,
  }) {
    return DeliveryState(
      customerName: customerName ?? this.customerName,
      pickupCoords: pickupCoords ?? this.pickupCoords,
      dropCoords: dropCoords ?? this.dropCoords,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      dropAddress: dropAddress ?? this.dropAddress,
      pickedUp: pickedUp ?? this.pickedUp,
      distanceTravelled: distanceTravelled ?? this.distanceTravelled,
    );
  }
}

class DeliveryNotifier extends StateNotifier<DeliveryState> {
  DeliveryNotifier() : super(DeliveryState());

  void setCustomer(String name) {
    state = state.copyWith(customerName: name);
  }

  void setPickup(GeoCoordinates coords, String address) {
    state = state.copyWith(pickupCoords: coords, pickupAddress: address);
  }

  void setDrop(GeoCoordinates coords, String address) {
    state = state.copyWith(dropCoords: coords, dropAddress: address);
  }

  void pickup() {
    state = state.copyWith(pickedUp: true);
  }

  void addDistance(double delta) {
    state = state.copyWith(distanceTravelled: state.distanceTravelled + delta);
  }

  void reset() {
    state = DeliveryState();
  }
}