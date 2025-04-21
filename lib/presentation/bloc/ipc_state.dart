// lib/presentation/bloc/ipc_state.dart
part of 'ipc_bloc.dart';

abstract class IpcState extends Equatable {
  const IpcState();

  @override
  List<Object?> get props => [];
}

// Initial state before any connection attempt
class IpcInitial extends IpcState {}

// State while connecting and subscribing
class IpcConnecting extends IpcState {}

// State when connected and listening, holds the latest data
class IpcConnected extends IpcState {
  final DisplayData? latestData; // Can be null initially

  const IpcConnected({this.latestData});

  @override
  List<Object?> get props => [latestData];

  // Helper for convenient updates
  IpcConnected copyWith({
    DisplayData? latestData,
  }) {
    return IpcConnected(
      latestData: latestData ?? this.latestData,
    );
  }
}

// State when disconnected (either intentionally or due to error)
class IpcDisconnected extends IpcState {
  final String? reason; // Optional reason for disconnection
  const IpcDisconnected({this.reason});

  @override
  List<Object?> get props => [reason];
}

// State representing an error during connection or operation
class IpcError extends IpcState {
  final String message;
  final dynamic originalError;

  const IpcError(this.message, {this.originalError});

  @override
  List<Object?> get props => [message, originalError];
}