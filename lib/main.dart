import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ffi/ffi.dart';

// FFI definitions for C interface
final class DisplayData extends Struct {
  @Uint32()
  external int bms_errors;

  @Uint32()
  external int mcu_errors;

  @Uint32()
  external int obc_errors;

  @Uint32()
  external int plc_errors;

  @Uint32()
  external int vcu_errors;

  @Float()
  external double battery_temp;

  @Float()
  external double throttle;

  @Float()
  external double speed;

  @Float()
  external double battery_soc;

  @Uint8()
  external int abs_status;

  @Uint8()
  external int drivemode;

  @Uint8()
  external int dpad;

  @Uint8()
  external int killsw;

  @Uint8()
  external int highbeam;

  @Uint8()
  external int indicators;
}

// Define the IpcSubscriber struct from the C code
final class IpcSubscriber extends Struct {
  external Pointer<Utf8> topic_name;
  @Int32()
  external int sockfd;
}

// Error codes from the C library
class IpcErrors {
  static const int ESOCKINIT = -1;
  static const int ESOCKBIND = -2;
  static const int ESOCKSEND = -3;
  static const int ESOCKRECV = -4;
  static const int EINVAL = -5;
}

// C library interface
class IPCLib {
  late DynamicLibrary _lib;
  late int Function() _ipcInit;
  late int Function(Pointer<IpcSubscriber>) _ipcSubscribe;
  late int Function(Pointer<IpcSubscriber>) _ipcPoll;
  late int Function() _ipcClose;

  IPCLib() {
    // Load the dynamic library
    _lib = DynamicLibrary.open('libipc.so');

    // Get function references
    _ipcInit = _lib
        .lookup<NativeFunction<Int32 Function()>>('ipcInit')
        .asFunction();

    _ipcSubscribe = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<IpcSubscriber>)>>('ipcSubscribe')
        .asFunction();

    _ipcPoll = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<IpcSubscriber>, Pointer<Void>, Uint16)>>('ipcPoll')
        .asFunction<int Function(Pointer<IpcSubscriber>, Pointer<Void>, int)>() as int Function(Pointer<IpcSubscriber> p1);

    _ipcClose = _lib
        .lookup<NativeFunction<Int32 Function()>>('ipcClose')
        .asFunction();
  }

  int initIPC() {
    return _ipcInit();
  }

  int subscribeToTopic(String topicName) {
    final subscriber = calloc<IpcSubscriber>();
    subscriber.ref.topic_name = topicName.toNativeUtf8();

    final result = _ipcSubscribe(subscriber);

    // Note: In a real implementation, we would store the subscriber pointer
    // to use with ipcPoll, but for simplicity here we're going to use the Unix socket directly

    calloc.free(subscriber.ref.topic_name);
    calloc.free(subscriber);

    return result;
  }

  int closeIPC() {
    return _ipcClose();
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPC Display Data',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const DataDisplayScreen(),
    );
  }
}

class DataDisplayScreen extends StatefulWidget {
  const DataDisplayScreen({Key? key}) : super(key: key);

  @override
  State<DataDisplayScreen> createState() => _DataDisplayScreenState();
}

class _DataDisplayScreenState extends State<DataDisplayScreen> {
  // Model data
  DisplayDataModel? displayData;
  String connectionStatus = "Initializing...";
  Socket? socket;
  Timer? reconnectTimer;
  bool isConnected = false;
  int clientId = 0;

  // Model enums
  final driveModes = ["COMFORT", "POWER", "SPRINT", "REVERSE"];
  final absStatuses = ["NORMAL", "WARNING", "ERROR"];

  @override
  void initState() {
    super.initState();
    _initializeIPC();
  }

  @override
  void dispose() {
    socket?.close();
    reconnectTimer?.cancel();
    super.dispose();
  }

  void _initializeIPC() async {
    try {
      setState(() {
        connectionStatus = "Initializing IPC...";
      });

      // Initialize the IPC
      final ipcLib = IPCLib();
      final initResult = ipcLib.initIPC();

      if (initResult < 0) {
        setState(() {
          connectionStatus = "Failed to initialize IPC: Error $initResult";
        });
        return;
      }

      // Client ID was successfully obtained
      clientId = initResult;

      setState(() {
        connectionStatus = "IPC initialized. Client ID: $clientId";
      });

      // Subscribe to the DisplayData topic
      final subscribeResult = ipcLib.subscribeToTopic("DisplayData");
      if (subscribeResult < 0) {
        setState(() {
          connectionStatus = "Failed to subscribe to DisplayData: Error $subscribeResult";
        });
        return;
      }

      setState(() {
        connectionStatus = "Subscribed to DisplayData topic";
      });

      // Connect to the socket directly - this is an alternative to using ipcPoll
      // which is more suitable for a Flutter app
      _connectToSocket();

    } catch (e) {
      setState(() {
        connectionStatus = "Error initializing IPC: $e";
      });
    }
  }

  void _connectToSocket() async {
    final socketPath = '/tmp/$clientId-DisplayData';

    try {
      setState(() {
        connectionStatus = "Connecting to socket at $socketPath...";
      });

      socket = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0
      ).timeout(const Duration(seconds: 5));

      setState(() {
        connectionStatus = "Connected to socket at $socketPath";
        isConnected = true;
      });

      // Set up data listener
      socket!.listen(
            (Uint8List data) {
          _processReceivedData(data);
        },
        onError: (error) {
          setState(() {
            connectionStatus = "Socket error: $error";
            isConnected = false;
          });
          _scheduleReconnect();
        },
        onDone: () {
          setState(() {
            connectionStatus = "Connection closed";
            isConnected = false;
          });
          _scheduleReconnect();
        },
      );
    } catch (e) {
      setState(() {
        connectionStatus = "Connection error: $e";
        isConnected = false;
      });
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!isConnected && mounted) {
        _connectToSocket();
      }
    });
  }

  void _processReceivedData(Uint8List data) {
    // Since we can't create DisplayData directly (it's a Struct), we'll parse the data
    // into our own model class
    if (data.length < 42) { // Size of DisplayData struct
      print("Received incomplete data packet");
      return;
    }

    // Convert the data to a ByteData for easier reading
    final byteData = ByteData.sublistView(data);

    // Create DisplayData model and parse the binary data
    setState(() {
      displayData = DisplayDataModel(
          bms_errors: byteData.getUint32(0, Endian.little),
          mcu_errors: byteData.getUint32(4, Endian.little),
          obc_errors: byteData.getUint32(8, Endian.little),
          plc_errors: byteData.getUint32(12, Endian.little),
          vcu_errors: byteData.getUint32(16, Endian.little),
          battery_temp: byteData.getFloat32(20, Endian.little),
          throttle: byteData.getFloat32(24, Endian.little),
          speed: byteData.getFloat32(28, Endian.little),
          battery_soc: byteData.getFloat32(32, Endian.little),
          abs_status: byteData.getUint8(36),
          drivemode: byteData.getUint8(37),
          dpad: byteData.getUint8(38),
          killsw: byteData.getUint8(39),
          highbeam: byteData.getUint8(40),
          indicators: byteData.getUint8(41)
      );
    });
  }

  String getDriveModeString(int mode) {
    if (mode >= 0 && mode < driveModes.length) {
      return driveModes[mode];
    }
    return "UNKNOWN";
  }

  String getAbsStatusString(int status) {
    if (status >= 0 && status < absStatuses.length) {
      return absStatuses[status];
    }
    return "UNKNOWN";
  }

  String getDpadDirectionString(int dpad) {
    List<String> active = [];
    if ((dpad & 0x01) != 0) active.add("LEFT");
    if ((dpad & 0x02) != 0) active.add("UP");
    if ((dpad & 0x04) != 0) active.add("RIGHT");
    if ((dpad & 0x08) != 0) active.add("BOTTOM");

    return active.isEmpty ? "NONE" : active.join(", ");
  }

  String getIndicatorsString(int indicators) {
    List<String> active = [];
    if ((indicators & 0x01) != 0) active.add("LEFT");
    if ((indicators & 0x02) != 0) active.add("RIGHT");

    return active.isEmpty ? "NONE" : active.join(", ");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Display Data'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection status
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: isConnected ? Colors.green.shade900 : Colors.red.shade900,
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.check_circle : Icons.error,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connectionStatus,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (!isConnected)
                    TextButton(
                      onPressed: _connectToSocket,
                      child: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Display data
            if (displayData != null) ...[
              // Primary data section
              _buildDataSection(
                title: 'Basic Information',
                children: [
                  _buildDataRow('Speed', '${displayData!.speed.toStringAsFixed(1)} km/h'),
                  _buildDataRow('Battery SOC', '${(displayData!.battery_soc * 100).toStringAsFixed(1)}%'),
                  _buildDataRow('Battery Temp', '${displayData!.battery_temp.toStringAsFixed(1)}°C'),
                  _buildDataRow('Throttle', '${(displayData!.throttle * 100).toStringAsFixed(1)}%'),
                ],
              ),

              const SizedBox(height: 20),

              // Status indicators
              _buildDataSection(
                title: 'Vehicle Status',
                children: [
                  _buildDataRow('Drive Mode', getDriveModeString(displayData!.drivemode)),
                  _buildDataRow('ABS Status', getAbsStatusString(displayData!.abs_status)),
                  _buildDataRow('Kill Switch', displayData!.killsw == 1 ? 'ON' : 'OFF'),
                  _buildDataRow('High Beam', displayData!.highbeam == 1 ? 'ON' : 'OFF'),
                  _buildDataRow('D-Pad', getDpadDirectionString(displayData!.dpad)),
                  _buildDataRow('Indicators', getIndicatorsString(displayData!.indicators)),
                ],
              ),

              const SizedBox(height: 20),

              // Error counters
              _buildDataSection(
                title: 'System Errors',
                children: [
                  _buildDataRow('BMS Errors', displayData!.bms_errors.toString()),
                  _buildDataRow('MCU Errors', displayData!.mcu_errors.toString()),
                  _buildDataRow('OBC Errors', displayData!.obc_errors.toString()),
                  _buildDataRow('PLC Errors', displayData!.plc_errors.toString()),
                  _buildDataRow('VCU Errors', displayData!.vcu_errors.toString()),
                ],
              ),
            ] else if (isConnected) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('Waiting for data...'),
                ),
              ),
              const Center(child: CircularProgressIndicator()),
            ] else ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('Connecting to IPC...'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataSection({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }
}

// A Dart model class for the DisplayData struct
class DisplayDataModel {
  final int bms_errors;
  final int mcu_errors;
  final int obc_errors;
  final int plc_errors;
  final int vcu_errors;
  final double battery_temp;
  final double throttle;
  final double speed;
  final double battery_soc;
  final int abs_status;
  final int drivemode;
  final int dpad;
  final int killsw;
  final int highbeam;
  final int indicators;

  DisplayDataModel({
    required this.mcu_errors,
    required this.obc_errors,
    required this.plc_errors,
    required this.vcu_errors,
    required this.battery_temp,
    required this.throttle,
    required this.speed,
    required this.battery_soc,
    required this.abs_status,
    required this.drivemode,
    required this.dpad,
    required this.killsw,
    required this.highbeam,
    required this.indicators,
    required this.bms_errors,
  });
}