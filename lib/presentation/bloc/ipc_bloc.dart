// lib/presentation/bloc/ipc_bloc.dart
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../data/models/display_data.dart';
import '../../services/ipc_service.dart';
import '../../core/error/exceptions.dart'; // Import exceptions

part 'ipc_event.dart';
part 'ipc_state.dart';

class IpcBloc extends Bloc<IpcEvent, IpcState> {
  final IpcService _ipcService;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _errorSubscription; // If service exposes separate error stream

  IpcBloc(this._ipcService) : super(IpcInitial()) {
    on<ConnectIpc>(_onConnectIpc);
    on<DisconnectIpc>(_onDisconnectIpc);
    on<_IpcDataReceived>(_onDataReceived);
    on<_IpcErrorOccurred>(_onErrorOccurred);

    // Listen to the service's stream immediately if needed, or wait for ConnectIpc
    _listenToServiceStreams();
  }

  void _listenToServiceStreams() {
    // Cancel previous subscriptions if any
    _dataSubscription?.cancel();
    // Assuming service exposes data via dataStream
    _dataSubscription = _ipcService.dataStream.listen(
            (data) => add(_IpcDataReceived(data)),
        onError: (error) => add(_IpcErrorOccurred(error)),
        onDone: () {
          // Service stream closed, means connection is likely lost
          if (state is IpcConnected || state is IpcConnecting) {
            add(DisconnectIpc()); // Trigger disconnect state
          }
        }
    );

    // If IpcService had a dedicated error stream, subscribe here too
    // _errorSubscription = _ipcService.errorStream.listen(...)
  }

  Future<void> _onConnectIpc(ConnectIpc event, Emitter<IpcState> emit) async {
    // Prevent multiple connection attempts
    if (state is IpcConnecting || state is IpcConnected) return;

    emit(IpcConnecting());
    try {
      await _ipcService.initializeAndSubscribe();
      // Once subscribed successfully, move to Connected state
      // Initial data might be null until the first message arrives
      emit(const IpcConnected(latestData: null));
      // Ensure listeners are active *after* potential re-initialization
      _listenToServiceStreams();
    } on IpcException catch (e) {
      print("IPC BLoC: Connection Error: $e");
      emit(IpcError("Connection failed: ${e.message}", originalError: e));
      // Ensure service is cleaned up if init failed halfway
      await _ipcService.dispose();
      emit(const IpcDisconnected(reason: "Connection failed"));
    } catch (e) {
      print("IPC BLoC: Unexpected Connection Error: $e");
      emit(IpcError("Unexpected connection error: $e", originalError: e));
      await _ipcService.dispose();
      emit(const IpcDisconnected(reason: "Unexpected connection error"));
    }
  }

  Future<void> _onDisconnectIpc(DisconnectIpc event, Emitter<IpcState> emit) async {
    // Only disconnect if actually connected or connecting
    if (state is IpcInitial || state is IpcDisconnected) return;

    final previousState = state; // Store state before emitting disconnect

    emit(const IpcDisconnected(reason: "User initiated disconnect")); // Optimistic update
    try {
      await _dataSubscription?.cancel(); // Stop listening
      _dataSubscription = null;
      await _ipcService.dispose(); // Tell service to close sockets etc.
      print("IPC BLoC: Disconnected successfully.");
    } catch (e) {
      print("IPC BLoC: Error during disconnect: $e");
      // Even if dispose fails, stay in disconnected state
      // Optionally revert to an error state if disconnect fails critically?
      if (previousState is! IpcDisconnected){ // Avoid emitting error if already disconnected
        emit(IpcError("Error during disconnection: $e", originalError: e));
        // Still try to stay logically disconnected
        emit(const IpcDisconnected(reason: "Error during disconnect"));
      }
    }
  }

  void _onDataReceived(_IpcDataReceived event, Emitter<IpcState> emit) {
    // Only update data if we are in the connected state
    if (state is IpcConnected) {
      // Cast state and emit a new state with updated data
      emit((state as IpcConnected).copyWith(latestData: event.data));
    } else {
      print("IPC BLoC: Received data but not in Connected state. Current state: $state");
    }
  }

  void _onErrorOccurred(_IpcErrorOccurred event, Emitter<IpcState> emit) {
    print("IPC BLoC: Service Stream Error: ${event.error}");
    String errorMessage = "An IPC error occurred";
    if (event.error is IpcException) {
      errorMessage = (event.error as IpcException).message;
    } else if (event.error is Exception) {
      errorMessage = event.error.toString();
    }
    // Transition to an Error state AND Disconnected state
    emit(IpcError(errorMessage, originalError: event.error));
    emit(IpcDisconnected(reason: "Error: $errorMessage"));
    // Trigger cleanup in the service layer
    _ipcService.dispose(); // Ensure resources are released on error
  }

  @override
  Future<void> close() {
    // Ensure resources are cleaned up when the BLoC is closed
    print("IPC BLoC: Closing...");
    _dataSubscription?.cancel();
    _ipcService.dispose(); // Crucial: Close sockets etc.
    return super.close();
  }
}