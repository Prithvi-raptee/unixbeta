// lib/presentation/bloc/ipc_event.dart
part of 'ipc_bloc.dart';

abstract class IpcEvent extends Equatable {
  const IpcEvent();

  @override
  List<Object> get props => [];
}

// Event to trigger connection and subscription
class ConnectIpc extends IpcEvent {}

// Event to trigger disconnection and cleanup
class DisconnectIpc extends IpcEvent {}

// Internal event when new data is received from the service
class _IpcDataReceived extends IpcEvent {
  final DisplayData data;
  const _IpcDataReceived(this.data);

  @override
  List<Object> get props => [data];
}

// Internal event when an error occurs in the service stream
class _IpcErrorOccurred extends IpcEvent {
  final dynamic error;
  const _IpcErrorOccurred(this.error);

  @override
  List<Object> get props => [error];
}