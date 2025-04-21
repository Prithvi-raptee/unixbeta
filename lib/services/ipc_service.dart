import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/constants/ipc_constants.dart';
import '../core/error/exceptions.dart';
import '../data/models/display_data.dart'; // Includes helpers
// Define a simple result class for the isolate
class _IsolateInitResult {
  final int? clientId;
  final String? errorMessage;
  final dynamic originalException;

  _IsolateInitResult({this.clientId, this.errorMessage, this.originalException});

  bool get isSuccess => clientId != null && errorMessage == null;
}

Future<_IsolateInitResult> _performIpcInitIsolate(Map<String, dynamic> args) async {
  // Extract arguments (safer than positional)
  final String masterPath = args['masterPath'];
  final String clientDefaultPath = args['clientDefaultPath'];
  final int registerClientCode = args['registerClientCode'];
  final Duration timeoutDuration = args['timeout'];

  print("IPC Isolate: Starting initialization...");
  RawDatagramSocket? tempSocket;
  InternetAddress? masterAddress;

  // Simplified helper functions for use within isolate (or use top-level ones)
  // --- Start Simplified Helpers (Replace with actual top-level/imported helpers) ---
  Future<void> _unlinkQuietlyIsolate(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) { await file.delete(); print("IPC Isolate: Unlinked '$path'"); }
    } catch (e) { print("IPC Isolate Warning: Failed to unlink '$path': $e"); }
  }

  Future<RawDatagramSocket> _safeSocketBindIsolate(String path, int port) async {
    await _unlinkQuietlyIsolate(path);
    // No delay needed here, isolate handles potential blocking
    print("IPC Isolate: Binding '$path'...");
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress(path, type: InternetAddressType.unix), port);
      print("IPC Isolate: Bound '$path' successfully.");
      return socket;
    } catch(e,s) {
      print("IPC Isolate: Bind error for '$path': $e\n$s");
      await _unlinkQuietlyIsolate(path); // Cleanup on error
      rethrow; // Let the main catch block handle it
    }
  }

  Future<Datagram?> _receiveWithTimeoutIsolate(RawDatagramSocket socket, Duration timeout, String opDesc) async {
    // Basic implementation - use your more robust one if possible as top-level
    Completer<Datagram?> completer = Completer();
    StreamSubscription? sub;
    Timer? timer;
    try {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.completeError(TimeoutException("Timeout: $opDesc"));
      });
      sub = socket.listen(
              (event) {
            if(event == RawSocketEvent.read && !completer.isCompleted) {
              final dg = socket.receive();
              if(dg != null) completer.complete(dg);
            } else if (event == RawSocketEvent.closed && !completer.isCompleted) {
              completer.completeError(Exception("Socket closed: $opDesc"));
            }
          },
          onError: (e, s) { if (!completer.isCompleted) completer.completeError(e, s); },
          onDone: () { if (!completer.isCompleted) completer.completeError(Exception("Socket done: $opDesc")); },
          cancelOnError: true
      );
      return await completer.future;
    } finally {
      timer?.cancel();
      await sub?.cancel();
    }
  }
  // --- End Simplified Helpers ---


  try {
    // 1. Create master address
    try {
      masterAddress = InternetAddress(masterPath, type: InternetAddressType.unix);
      print("IPC Isolate: Created master address: ${masterAddress.address}");
    } catch (e) {
      throw Exception("Error creating master address for '$masterPath': $e");
    }

    // 2. Bind temporary socket
    tempSocket = await _safeSocketBindIsolate(clientDefaultPath, 0);
    print("IPC Isolate: Bound temporary socket: ${tempSocket.address.address}:${tempSocket.port}");

    // 3. Send registration request
    // Ensure serializeClientMessage is accessible (top-level or passed/redefined)
    final registerMsg = serializeClientMessage(requestType: registerClientCode);
    final sentBytes = tempSocket.send(registerMsg, masterAddress, 0);
    if (sentBytes == 0) {
      throw Exception("Failed to send registration request (0 bytes sent).");
    }
    print("IPC Isolate: Sent registration request (${registerMsg.length} bytes) to master '${masterAddress.address}'");

    // 4. Wait for response
    final datagram = await _receiveWithTimeoutIsolate(tempSocket, timeoutDuration, "isolate registration response");
    if (datagram == null) {
      throw Exception("Did not receive a valid registration response datagram (null).");
    }
    print("IPC Isolate: Received registration response (${datagram.data.length} bytes).");

    // 5. Parse response
    // Ensure MasterMessage is accessible (imported or passed/redefined)
    final responseData = Uint8List.fromList(datagram.data);
    final masterResponse = MasterMessage.fromBytes(responseData);

    if (masterResponse.status < 0) {
      throw Exception("Master returned error during registration (Status: ${masterResponse.status})");
    }

    final receivedClientId = masterResponse.clientId;
    if (receivedClientId <= 0) {
      throw Exception("Master returned invalid client ID ($receivedClientId)");
    }
    print("IPC Isolate: Received Client ID: $receivedClientId");

    // 6. Clean up temporary socket
    tempSocket.close();
    await _unlinkQuietlyIsolate(clientDefaultPath);
    tempSocket = null;
    print("IPC Isolate: Cleaned up temporary socket '$clientDefaultPath'.");

    // 7. Success: Return client ID
    print("IPC Isolate: Initialization successful.");
    return _IsolateInitResult(clientId: receivedClientId);

  } catch (e, s) {
    print("IPC Isolate: Error during initialization phase: $e");
    print("IPC Isolate: Stacktrace: $s");
    // Clean up temp socket if it exists on error
    if (tempSocket != null) {
      tempSocket.close();
      await _unlinkQuietlyIsolate(clientDefaultPath);
      print("IPC Isolate: Cleaned up temporary socket '$clientDefaultPath' after error.");
    }
    return _IsolateInitResult(errorMessage: e.toString(), originalException: e);
  }
}


// Assume these constants are defined elsewhere
// const String ipcMasterPath = '/tmp/ipc_master';
// const String ipcClientDefaultPath = '/tmp/client'; // Default path for initial contact
// const String displayDataTopic = 'DisplayData';
// String clientSpecificPath(int clientId) => '/tmp/$clientId';
// String clientTopicPath(int clientId, String topic) => '/tmp/$clientId-$topic';
// const int ipcRegisterClient = 1;
// const int ipcRegisterSubscriber = 2;
// const int ipcDeregisterSubscriber = 3;

class IpcService {
  RawDatagramSocket? _masterCommSocket; // Socket for talking TO the master (init, subscribe, unsubscribe)
  RawDatagramSocket? _dataSubscriptionSocket; // Socket for receiving data FROM master
  StreamSubscription<RawSocketEvent>? _dataSubscriptionListener;
  InternetAddress? _masterAddress; // Resolved address object for sending to master
  int? _clientId;
  String? _clientSpecificPath; // Path for _masterCommSocket (e.g., /tmp/123)
  String? _clientTopicPath; // Path for _dataSubscriptionSocket (e.g., /tmp/123-DisplayData)

  StreamController<DisplayData> _dataController = StreamController<DisplayData>.broadcast();
  Stream<DisplayData> get dataStream => _dataController.stream;

  // --- Public API ---

  Future<void> initializeAndSubscribe() async {
    if (_clientId != null) {
      print("IPC Service: Already initialized (Client ID: $_clientId).");
      return;
    }
    if (_dataController.isClosed) {
      _dataController = StreamController<DisplayData>.broadcast();
      print("IPC Service: Recreated closed data stream controller.");
    }

    print("IPC Service: Initializing...");
    try {
      // 0. Basic check if master path exists
      await _ensureMasterPathAvailable();

      // 1. Create the master address object (needed for sending)
      await _createMasterAddress();

      // 2. Perform ipcInit equivalent (gets clientID, creates _masterCommSocket)
      _clientId = await _performIpcInit();
      print("IPC Service: Successfully initialized client comms (Client ID: $_clientId).");

      // Store paths associated with this client ID
      _clientSpecificPath = clientSpecificPath(_clientId!);
      _clientTopicPath = clientTopicPath(_clientId!, displayDataTopic);

      // 3. Perform ipcSubscribe equivalent (creates _dataSubscriptionSocket)
      await _performIpcSubscribe();
      print("IPC Service: Successfully subscribed to topic '$displayDataTopic' on path '$_clientTopicPath'");

      // 4. Start listening on the data socket
      _startListeningForData();
      print("IPC Service: Started listening for data.");

    } catch (e, s) { // Capture stack trace for better debugging
      print("IPC Service: Initialization failed: $e");
      print("IPC Service: Stacktrace:\n$s"); // Print stack trace
      await dispose(); // Clean up any partial initialization
      if (e is IpcException) {
        throw e; // Re-throw specific IPC exceptions
      } else {
        // Wrap unexpected errors
        throw IpcConnectionException("Failed to initialize IPC: ${e.toString()}", originalException: e);
      }
    }
  }

  Future<void> dispose() async {
    print("IPC Service: Disposing...");
    // Stop listening first
    await _dataSubscriptionListener?.cancel();
    _dataSubscriptionListener = null;
    print("IPC Service: Cancelled data subscription listener.");

    // Check if fully initialized before attempting unsubscribe
    bool wasInitialized = _clientId != null && _masterCommSocket != null && _masterAddress != null;

    if (wasInitialized) {
      try {
        // Only attempt unsubscribe if the comm socket seems valid (best effort)
        print("IPC Service: Attempting to send unsubscribe message...");
        // No await here, fire and forget is often okay for unsubscribe
        _performIpcUnsubscribe(); // Changed to fire-and-forget style
        print("IPC Service: Unsubscribe message attempt initiated for topic '$displayDataTopic'.");
      } catch (e, s) {
        // Log error if sending itself fails, but don't block disposal
        print("IPC Service: Error attempting to send unsubscribe message: $e\n$s");
      }
    } else {
      print("IPC Service: Skipping unsubscribe (not fully initialized or already disposed).");
    }

    // Close sockets FIRST
    // Use try-catch around close just in case, although unlikely to fail often
    try {
      _dataSubscriptionSocket?.close();
      print("IPC Service: Closed data subscription socket ($_clientTopicPath).");
    } catch (e) {
      print("IPC Service Warning: Error closing data subscription socket: $e");
    } finally {
      _dataSubscriptionSocket = null;
    }

    try {
      _masterCommSocket?.close();
      print("IPC Service: Closed master communication socket ($_clientSpecificPath).");
    } catch (e) {
      print("IPC Service Warning: Error closing master communication socket: $e");
    } finally {
      _masterCommSocket = null;
    }


    // THEN unlink paths
    if (_clientTopicPath != null) {
      await _unlinkQuietly(_clientTopicPath!);
      _clientTopicPath = null; // Nullify after unlink attempt
    }
    if (_clientSpecificPath != null) {
      await _unlinkQuietly(_clientSpecificPath!);
      _clientSpecificPath = null; // Nullify after unlink attempt
    }
    // Also attempt to unlink the default path if disposal happened early
    await _unlinkQuietly(ipcClientDefaultPath);


    // Close the stream controller if not already closed
    if (!_dataController.isClosed) {
      await _dataController.close();
      print("IPC Service: Closed data stream controller.");
    }

    // Reset state variables
    _clientId = null;
    _masterAddress = null;
    print("IPC Service: Disposal complete.");
  }

  // --- Internal Logic ---

  Future<void> _ensureMasterPathAvailable() async {
    final masterFile = File(ipcMasterPath);
    if (!await masterFile.exists()) {
      print("IPC Service: Master path '$ipcMasterPath' not found, waiting briefly...");
      await Future.delayed(const Duration(milliseconds: 250)); // Slightly longer wait?
      if (!await masterFile.exists()) {
        throw IpcConnectionException("IPC Master socket path '$ipcMasterPath' does not exist after waiting. Is the master process running and ready?");
      }
    }
    // Check type (optional but good)
    final fileStat = await masterFile.stat();
    if(fileStat.type != FileSystemEntityType.unixDomainSock) {
      print("IPC Service Warning: Master path '$ipcMasterPath' exists but is not a socket (${fileStat.type}).");
      // Depending on requirements, you might throw an error here
      // throw IpcConnectionException("IPC Master path '$ipcMasterPath' is not a Unix Domain Socket.");
    }
    print("IPC Service: Master path '$ipcMasterPath' found and appears to be a socket.");
  }

  Future<void> _createMasterAddress() async {
    print("IPC Service: Creating master address for '$ipcMasterPath'...");
    try {
      // Resolution is simple for Unix paths, just creates the address object
      _masterAddress = InternetAddress(ipcMasterPath, type: InternetAddressType.unix);
      print("IPC Service: Created master address object: ${_masterAddress?.address}");
    } catch (e) {
      throw IpcConnectionException("Error creating master address object for '$ipcMasterPath': $e", originalException: e);
    }
  }

  // Updated binding method with a delay before binding
  Future<RawDatagramSocket> _safeSocketBind(String path, int port) async {
    print("IPC Service: Preparing to bind socket at '$path'...");
    // Ensure the path is unlinked before binding
    await _unlinkQuietly(path);

    try {
      // *** FIX: Introduce a tiny delay before binding ***
      // This yields execution, potentially allowing the Dart VM/event loop
      // to reach a state where the async bind callback is allowed.
      print("IPC Service: Yielding before binding '$path'...");
      await Future.delayed(Duration.zero);
      print("IPC Service: Proceeding with bind for '$path'...");

      // Direct binding
      final socket = await RawDatagramSocket.bind(
          InternetAddress(path, type: InternetAddressType.unix),
          port // port is usually 0 for Unix client sockets to get an ephemeral binding internally
      );
      print("IPC Service: Successfully bound socket to '$path' (local port: ${socket.port})");
      return socket;
    } catch (e, s) {
      print("IPC Service: Socket binding error for '$path': $e\n$s");
      // Attempt cleanup if bind failed
      await _unlinkQuietly(path);
      throw IpcConnectionException("Failed to bind socket at '$path': $e", originalException: e); // Throw a specific exception
    }
  }

  // Helper for receiving a datagram with timeout (mostly unchanged, minor logging improvements)
  // Helper for receiving a datagram with timeout (mostly unchanged, minor logging improvements)
  Future<Datagram?> _receiveWithTimeout(RawDatagramSocket socket, Duration timeout, String operationDescription) async {
    Completer<Datagram?> completer = Completer();
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    // *** FIX: Use .address instead of .path ***
    final socketAddr = "${socket.address.address}:${socket.port}"; // For logging

    try {
      print("IPC Service: [$socketAddr] Waiting for '$operationDescription' (timeout: ${timeout.inMilliseconds}ms)...");

      subscription = socket.listen(
            (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            // Potential issue: Can receive multiple read events before processing.
            // Only complete on the first valid datagram.
            if (!completer.isCompleted) {
              final received = socket.receive();
              if (received != null) {
                print("IPC Service: [$socketAddr] Received datagram for '$operationDescription' (${received.data.length} bytes).");
                timer?.cancel();
                completer.complete(received);
              } else {
                // This case might happen if the read event was for an empty datagram or EOF?
                print("IPC Service Warning: [$socketAddr] Read event for '$operationDescription', but receive() returned null.");
                // Don't complete here, wait for another read or timeout/close.
              }
            } else {
              print("IPC Service: [$socketAddr] Received duplicate read event for '$operationDescription' after completion.");
              // Drain the socket to avoid subsequent reads on the same data?
              socket.receive();
            }
          } else if (event == RawSocketEvent.readClosed || event == RawSocketEvent.closed) {
            if (!completer.isCompleted) {
              print("IPC Service Error: [$socketAddr] Socket closed while waiting for '$operationDescription'. Event: $event");
              timer?.cancel();
              completer.completeError(IpcConnectionException("Socket closed unexpectedly while waiting for $operationDescription."));
            }
          }
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            print("IPC Service Error: [$socketAddr] Listener error waiting for '$operationDescription': $error\n$stackTrace");
            timer?.cancel();
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            print("IPC Service Warning: [$socketAddr] Socket stream closed (onDone) while waiting for '$operationDescription'.");
            timer?.cancel();
            // Complete with error as we didn't get the expected data before close
            completer.completeError(IpcConnectionException("Socket stream closed (onDone) before receiving $operationDescription."));
          }
        },
        cancelOnError: true,
      );

      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          print("IPC Service Error: [$socketAddr] Timeout waiting for '$operationDescription'.");
          completer.completeError(TimeoutException("Timeout waiting for $operationDescription.", timeout));
          // No need to cancel subscription here, finally block handles it.
        }
      });

      return await completer.future;

    } catch(e) {
      print("IPC Service: Error in _receiveWithTimeout for '$operationDescription': $e");
      // Ensure cleanup happens even if future throws before await
      await subscription?.cancel();
      timer?.cancel();
      rethrow; // Rethrow the original error (likely TimeoutException or IpcConnectionException)
    }
    finally {
      // Ensure subscription is always cancelled
      await subscription?.cancel();
      timer?.cancel();
    }
  }

  Future<int> _performIpcInit() async {
    print("IPC Service: >>> Entering _performIpcInit function (using Isolate)...");
    const Duration receiveTimeout = Duration(seconds: 5); // Timeout for isolate comms itself

    if (_masterAddress == null) {
      // This check should ideally happen before calling _performIpcInit,
      // but keep it as a safeguard. Master address object isn't needed by isolate func.
      throw IpcConfigurationException("Master address object not created before calling _performIpcInit.");
    }

    try {
      print("IPC Service: Starting background isolate for initial IPC registration...");
      // Prepare arguments for the isolate function
      final isolateArgs = {
        'masterPath': ipcMasterPath,
        'clientDefaultPath': ipcClientDefaultPath,
        'registerClientCode': ipcRegisterClient,
        'timeout': receiveTimeout, // Pass timeout for internal use by isolate
      };

      // Run the initialization logic in a separate isolate
      // Isolate.run is simpler than managing Send/ReceivePorts directly
      final _IsolateInitResult result = await Isolate.run(() => _performIpcInitIsolate(isolateArgs));

      print("IPC Service: Background isolate completed.");

      // Process the result from the isolate
      if (result.isSuccess && result.clientId != null) {
        final receivedClientId = result.clientId!;
        print("IPC Service: Received Client ID $receivedClientId from isolate.");

        // *** IMPORTANT: Bind the PERMANENT socket on the MAIN isolate ***
        final clientPath = clientSpecificPath(receivedClientId);
        print("IPC Service: Binding permanent client communication socket ON MAIN ISOLATE to '$clientPath'");

        // Use the original _safeSocketBind (which includes the delay) for this bind,
        // just in case it helps here.
        _masterCommSocket = await _safeSocketBind(clientPath, 0);
        print("IPC Service: Bound final client communication socket successfully on main isolate: ${_masterCommSocket?.address.address}:${_masterCommSocket?.port}");

        return receivedClientId; // Success

      } else {
        // Isolate failed, rethrow an appropriate exception
        print("IPC Service: Isolate initialization failed: ${result.errorMessage}");
        if (result.originalException is Exception) {
          throw IpcConnectionException("IPC initialization in isolate failed: ${result.errorMessage}", originalException: result.originalException);
        } else {
          throw IpcConnectionException("IPC initialization in isolate failed: ${result.errorMessage}");
        }
      }
    } catch (e, s) {
      // Catch errors related to starting the isolate or processing its result
      print("IPC Service: Error during main isolate part of _performIpcInit or isolate execution: $e");
      print("IPC Service: StackTrace: $s");
      _masterCommSocket = null; // Ensure comm socket is null on failure
      // We don't need to clean up the temp socket here, isolate function handles that.
      rethrow; // Rethrow the caught exception
    }
  }

  Future<void> _performIpcSubscribe() async {
    if (_masterCommSocket == null || _masterAddress == null || _clientId == null) {
      throw IpcConfigurationException("Cannot subscribe: Client communication socket or client ID not ready.");
    }
    const Duration receiveTimeout = Duration(seconds: 5);

    RawDatagramSocket? dataSocketAttempt; // Temporary variable for the data socket
    final topicPath = clientTopicPath(_clientId!, displayDataTopic);

    try {
      // Create and bind the data subscription socket *before* sending request
      // This ensures the master can find the path when processing the request
      print("IPC Service: Binding data subscription socket to '$topicPath'");
      dataSocketAttempt = await _safeSocketBind(topicPath, 0);
      print("IPC Service: Bound data subscription socket successfully: ${dataSocketAttempt.address.address}:${dataSocketAttempt.port}");

      // Create and send subscribe request using the main comm socket
      final subscribeMsg = serializeClientMessage(
        requestType: ipcRegisterSubscriber,
        clientId: _clientId!,
        topicName: displayDataTopic,
      );
      final sentBytes = _masterCommSocket!.send(subscribeMsg, _masterAddress!, 0);
      if (sentBytes == 0) {
        throw IpcConnectionException("Failed to send subscribe request (0 bytes sent).");
      }
      print("IPC Service: Sent subscribe request for '$displayDataTopic' to master '${_masterAddress?.address}'.");

      // Wait for response on the main comm socket
      final datagram = await _receiveWithTimeout(_masterCommSocket!, receiveTimeout, "subscribe response");
      if (datagram == null) {
        throw IpcConnectionException("Did not receive a valid subscribe response datagram (null received).");
      }
      print("IPC Service: Received subscribe response (${datagram.data.length} bytes).");

      // Copy the data to safely parse it
      final responseData = Uint8List.fromList(datagram.data);
      MasterMessage masterResponse;
      try {
        masterResponse = MasterMessage.fromBytes(responseData);
      } catch (e) {
        throw IpcParsingException("Failed to parse subscribe response: $e", originalException: e);
      }

      if (masterResponse.status < 0) {
        // If master failed, clean up the data socket we created
        dataSocketAttempt.close();
        await _unlinkQuietly(topicPath);
        throw IpcMasterException("Master returned error during subscription for '$displayDataTopic'", masterStatusCode: masterResponse.status);
      }

      // Success! Assign the successfully bound socket
      _dataSubscriptionSocket = dataSocketAttempt;
      print("IPC Service: Subscription successful for '$displayDataTopic'. Data socket is ready.");


    } catch (e) {
      print("IPC Service: Error during ipcSubscribe phase for '$displayDataTopic': $e");
      // Clean up the data socket if it was created and not assigned on error
      if (_dataSubscriptionSocket == null && dataSocketAttempt != null) {
        dataSocketAttempt.close();
        await _unlinkQuietly(topicPath);
        print("IPC Service: Cleaned up data socket '$topicPath' after subscription error.");
      }
      _dataSubscriptionSocket = null; // Ensure it's null on failure
      rethrow; // Rethrow to be handled by initializeAndSubscribe
    }
  }

  // Send unsubscribe (fire and forget style for disposal)
  void _performIpcUnsubscribe() {
    if (_masterCommSocket == null || _masterAddress == null || _clientId == null) {
      print("IPC Service: Cannot send unsubscribe, client comms not ready.");
      return;
    }

    try {
      // Create and send unsubscribe request
      final unsubscribeMsg = serializeClientMessage(
        requestType: ipcDeregisterSubscriber,
        clientId: _clientId!,
        topicName: displayDataTopic,
      );
      final sentBytes = _masterCommSocket!.send(unsubscribeMsg, _masterAddress!, 0);
      if (sentBytes == 0) {
        print("IPC Service Warning: Failed to send unsubscribe request (0 bytes sent) for '$displayDataTopic'. Master might not clean up immediately.");
      } else {
        print("IPC Service: Sent unsubscribe request for '$displayDataTopic' to master.");
      }
      // Don't wait for a response during dispose.
    } catch (e) {
      // Log error but don't prevent disposal
      print("IPC Service Warning: Error sending ipcUnsubscribe message for '$displayDataTopic': $e");
    }
  }


  void _startListeningForData() {
    if (_dataSubscriptionSocket == null) {
      // This should ideally not happen if initialization flow is correct
      print("IPC Service CRITICAL: Cannot listen for data: Data socket is null. Forcing disposal.");
      _dataController.addError(IpcConfigurationException("Cannot listen, data socket is null."));
      dispose(); // Trigger cleanup
      return;
      // Alternatively: throw IpcConfigurationException("Cannot listen for data: Data socket not initialized.");
    }
    if (_dataSubscriptionListener != null) {
      print("IPC Service Warning: Data listener already active. Cancelling old one before starting new.");
      _dataSubscriptionListener!.cancel();
      _dataSubscriptionListener = null;
    }

    // *** FIX: Use .address instead of .path ***
    final String listenerPath = _clientTopicPath ?? _dataSubscriptionSocket!.address.address ?? "unknown-data-path";
    print("IPC Service: Attaching listener to data socket '$listenerPath'...");

    _dataSubscriptionListener = _dataSubscriptionSocket!.listen(
          (RawSocketEvent event) {
        // Protect against actions if controller is closed during processing
        if (_dataController.isClosed) {
          print("IPC Service Info: Data received on '$listenerPath' but stream controller is closed. Ignoring.");
          return;
        }

        if (event == RawSocketEvent.read) {
          final datagram = _dataSubscriptionSocket!.receive(); // receive can return null
          if (datagram != null && datagram.data.isNotEmpty) {
            // print("IPC Service DEBUG: Received ${datagram.data.length} bytes on '$listenerPath'"); // Verbose
            try {
              // Basic size check
              if (datagram.data.length >= displayDataStructSize) {
                // Make a defensive copy JUST before parsing/adding to stream
                // This is crucial if fromBytes or stream listeners are async
                final dataBytes = Uint8List.fromList(datagram.data);
                final displayData = DisplayData.fromBytes(dataBytes);
                // Check again if controller closed while parsing
                if (!_dataController.isClosed) {
                  _dataController.add(displayData);
                }
              } else {
                print("IPC Service Warning: Received data packet on '$listenerPath' with unexpected size (${datagram.data.length} bytes). Expected >= $displayDataStructSize bytes.");
                // Optionally add an error to the stream?
                // _dataController.addError(IpcParsingException('Received runt packet size ${datagram.data.length}'));
              }
            } catch (e, s) {
              print("IPC Service Error: Error processing received data on '$listenerPath': $e\n$s");
              if (!_dataController.isClosed) {
                // Add a more specific error type if possible (e.g., IpcParsingException)
                if (e is IpcException) {
                  _dataController.addError(e);
                } else {
                  _dataController.addError(IpcParsingException("Processing error: $e", originalException: e));
                }
              }
            }
          } else if (datagram == null) {
            print("IPC Service Warning: Received READ event on '$listenerPath' but socket.receive() returned null.");
          } else {
            // Empty datagram received
            print("IPC Service Info: Received empty datagram on '$listenerPath'.");
          }
        } else if (event == RawSocketEvent.closed || event == RawSocketEvent.readClosed) {
          print("IPC Service Error: Data subscription socket '$listenerPath' closed unexpectedly. Event: $event. Initiating dispose.");
          if (!_dataController.isClosed) {
            _dataController.addError(IpcConnectionException("Data socket '$listenerPath' closed unexpectedly."));
          }
          // Critical failure, trigger cleanup
          dispose();
        } else {
          print("IPC Service DEBUG: Unhandled socket event on '$listenerPath': $event");
        }
      },
      onError: (error, stackTrace) {
        print("IPC Service Error: Data subscription stream error for '$listenerPath': $error\n$stackTrace");
        if (!_dataController.isClosed) {
          _dataController.addError(IpcConnectionException("Data subscription stream error", originalException: error));
        }
        // Critical failure, trigger cleanup
        dispose();
      },
      onDone: () {
        print("IPC Service: Data subscription stream is done (socket closed) for '$listenerPath'.");
        // If dispose wasn't already called (e.g., by RawSocketEvent.closed handler), call it now.
        // Check _clientId to prevent dispose loops if already disposing.
        if (_clientId != null) {
          print("IPC Service: Initiating dispose because data stream is done.");
          dispose();
        }
      },
      cancelOnError: true,
    );
    print("IPC Service: Listener attached successfully to '$listenerPath'.");
  }

  Future<void> _unlinkQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        // Double check it's actually a socket before deleting? Optional.
        // var type = await FileStat.stat(path);
        // if(type.type == FileSystemEntityType.unixDomainSocket) { ... }
        await file.delete();
        print("IPC Service: Unlinked '$path'");
      } else {
        // print("IPC Service DEBUG: Path '$path' did not exist, no need to unlink.");
      }
    } catch (e) {
      // Log as warning, failure to unlink isn't always critical but can cause issues on next run
      print("IPC Service Warning: Failed to unlink socket file '$path': $e.");
    }
  }
}
