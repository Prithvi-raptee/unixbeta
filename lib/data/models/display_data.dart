// // lib/data/models/display_data.dart
// import 'dart:typed_data';
// import 'package:equatable/equatable.dart';
// import '../../core/constants/ipc_constants.dart';
// import '../../core/error/exceptions.dart';
//
// // Enums matching C code (optional but good for clarity)
// enum DriveMode { comfort, power, sprint, reverse }
// enum AbsStatus { normal, warning, error }
//
// class DisplayData extends Equatable {
//   final int bmsErrors;        // uint32_t
//   final int mcuErrors;        // uint32_t
//   final int obcErrors;        // uint32_t
//   final int plcErrors;        // uint32_t
//   final int vcuErrors;        // uint32_t
//   final double batteryTemp;   // float
//   final double throttle;      // float
//   final double speed;         // float
//   final double batterySoc;    // float
//   final AbsStatus absStatus;  // uint8_t -> enum
//   final DriveMode driveMode;  // uint8_t -> enum
//   // DPad bit flags
//   final bool dpadBottom;
//   final bool dpadRight;
//   final bool dpadUp;
//   final bool dpadLeft;
//   // Other flags
//   final bool killSwitch;      // uint8_t
//   final bool highBeam;        // uint8_t
//   // Indicator bit flags
//   final bool indicatorRight;
//   final bool indicatorLeft;
//
//   const DisplayData({
//     required this.bmsErrors,
//     required this.mcuErrors,
//     required this.obcErrors,
//     required this.plcErrors,
//     required this.vcuErrors,
//     required this.batteryTemp,
//     required this.throttle,
//     required this.speed,
//     required this.batterySoc,
//     required this.absStatus,
//     required this.driveMode,
//     required this.dpadBottom,
//     required this.dpadRight,
//     required this.dpadUp,
//     required this.dpadLeft,
//     required this.killSwitch,
//     required this.highBeam,
//     required this.indicatorRight,
//     required this.indicatorLeft,
//   });
//
//   // Factory constructor to parse from raw bytes
//   factory DisplayData.fromBytes(Uint8List data) {
//     if (data.lengthInBytes < displayDataStructSize) {
//       throw IpcParsingException(
//           'Received data length (${data.lengthInBytes}) is less than expected DisplayData size ($displayDataStructSize)');
//     }
//
//     // Use ByteData for structured access, assuming Little Endian
//     final byteData = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
//     int offset = 0;
//
//     try {
//       // Read uint32_t values
//       final bmsErrors = byteData.getUint32(offset, Endian.little);
//       offset += 4;
//       final mcuErrors = byteData.getUint32(offset, Endian.little);
//       offset += 4;
//       final obcErrors = byteData.getUint32(offset, Endian.little);
//       offset += 4;
//       final plcErrors = byteData.getUint32(offset, Endian.little);
//       offset += 4;
//       final vcuErrors = byteData.getUint32(offset, Endian.little);
//       offset += 4;
//
//       // Read float values
//       final batteryTemp = byteData.getFloat32(offset, Endian.little);
//       offset += 4;
//       final throttle = byteData.getFloat32(offset, Endian.little);
//       offset += 4;
//       final speed = byteData.getFloat32(offset, Endian.little);
//       offset += 4;
//       final batterySoc = byteData.getFloat32(offset, Endian.little);
//       offset += 4;
//
//       // Read uint8_t values and enums
//       final absStatusRaw = byteData.getUint8(offset);
//       offset += 1;
//       final driveModeRaw = byteData.getUint8(offset);
//       offset += 1;
//       final dpadRaw = byteData.getUint8(offset);
//       offset += 1;
//       final killswRaw = byteData.getUint8(offset);
//       offset += 1;
//       final highbeamRaw = byteData.getUint8(offset);
//       offset += 1;
//       final indicatorsRaw = byteData.getUint8(offset);
//       offset += 1; // This should bring offset to displayDataStructSize (42)
//
//       // Convert raw values to Dart types/enums
//       final absStatus = AbsStatus.values[absStatusRaw.clamp(0, AbsStatus.values.length - 1)];
//       final driveMode = DriveMode.values[driveModeRaw.clamp(0, DriveMode.values.length - 1)];
//
//       // Parse bitfields
//       // DPad: 0 0 0 0 BOTTOM RIGHT UP LEFT
//       final dpadBottom = (dpadRaw & 0x08) != 0; // Bit 3
//       final dpadRight = (dpadRaw & 0x04) != 0;  // Bit 2
//       final dpadUp = (dpadRaw & 0x02) != 0;     // Bit 1
//       final dpadLeft = (dpadRaw & 0x01) != 0;   // Bit 0
//
//       final killSwitch = killswRaw != 0;
//       final highBeam = highbeamRaw != 0;
//
//       // Indicators: 0 0 0 0 0 0 RIGHT LEFT
//       final indicatorRight = (indicatorsRaw & 0x02) != 0; // Bit 1
//       final indicatorLeft = (indicatorsRaw & 0x01) != 0;  // Bit 0
//
//       return DisplayData(
//         bmsErrors: bmsErrors,
//         mcuErrors: mcuErrors,
//         obcErrors: obcErrors,
//         plcErrors: plcErrors,
//         vcuErrors: vcuErrors,
//         batteryTemp: batteryTemp,
//         throttle: throttle,
//         speed: speed,
//         batterySoc: batterySoc,
//         absStatus: absStatus,
//         driveMode: driveMode,
//         dpadBottom: dpadBottom,
//         dpadRight: dpadRight,
//         dpadUp: dpadUp,
//         dpadLeft: dpadLeft,
//         killSwitch: killSwitch,
//         highBeam: highBeam,
//         indicatorRight: indicatorRight,
//         indicatorLeft: indicatorLeft,
//       );
//     } catch (e) {
//       throw IpcParsingException('Error parsing DisplayData bytes at offset $offset: $e', originalException: e);
//     }
//   }
//
//   @override
//   List<Object?> get props => [
//     bmsErrors, mcuErrors, obcErrors, plcErrors, vcuErrors,
//     batteryTemp, throttle, speed, batterySoc,
//     absStatus, driveMode,
//     dpadBottom, dpadRight, dpadUp, dpadLeft,
//     killSwitch, highBeam,
//     indicatorRight, indicatorLeft,
//   ];
//
//   @override
//   String toString() {
//     return 'DisplayData('
//         'bmsErr: $bmsErrors, mcuErr: $mcuErrors, obcErr: $obcErrors, plcErr: $plcErrors, vcuErr: $vcuErrors, '
//         'batTemp: ${batteryTemp.toStringAsFixed(1)}C, throttle: ${throttle.toStringAsFixed(2)}, '
//         'speed: ${speed.toStringAsFixed(1)}km/h, soc: ${batterySoc.toStringAsFixed(1)}%, '
//         'abs: $absStatus, mode: $driveMode, kill: $killSwitch, highBeam: $highBeam, '
//         'dpad: L:$dpadLeft U:$dpadUp R:$dpadRight B:$dpadBottom, '
//         'ind: L:$indicatorLeft R:$indicatorRight'
//         ')';
//   }
// }
//
//
// // Helper function to serialize ClientMessage (used by IpcService)
// // typedef struct ClientMessage {
// //   uint8_t  request_type;
// //   uint8_t  client_id;
// //   char     topic_name[64];
// //   uint16_t data_size;
// //   uint8_t  data[MAX_DATA_SIZE]; // Not used for register/subscribe requests typically
// // } ClientMessage;
// Uint8List serializeClientMessage({
//   required int requestType,
//   int clientId = 0, // Usually 0 for initial registration
//   String topicName = "",
//   // data and data_size are omitted as they are 0 for reg/sub requests
// }) {
//   final builder = BytesBuilder();
//   // request_type (uint8_t)
//   builder.addByte(requestType);
//   // client_id (uint8_t)
//   builder.addByte(clientId);
//   // topic_name (char[64]) - null-padded ASCII
//   List<int> topicBytes = List.filled(maxTopicNameLength, 0);
//   List<int> nameBytes = Uint8List.fromList(topicName.codeUnits); // Assumes ASCII/UTF8 compatible
//   int len = nameBytes.length < maxTopicNameLength ? nameBytes.length : maxTopicNameLength -1; // Leave space for null term
//   topicBytes.setRange(0, len, nameBytes);
//   builder.add(topicBytes);
//   // data_size (uint16_t) - Little Endian
//   final sizeData = ByteData(2)..setUint16(0, 0, Endian.little); // Always 0 for reg/sub
//   builder.add(sizeData.buffer.asUint8List());
//   // data[MAX_DATA_SIZE] - Omitted as size is 0
//
//   return builder.toBytes();
// }
//
// // Helper function to parse MasterMessage
// // typedef struct MasterMessage {
// //   uint8_t client_id;
// //   int     status; // Using int32 for safety, C 'int' size varies
// // } MasterMessage;
// class MasterMessage {
//   final int clientId;
//   final int status;
//
//   MasterMessage(this.clientId, this.status);
//
//   factory MasterMessage.fromBytes(Uint8List data) {
//     if (data.lengthInBytes < 5) { // 1 byte client_id + 4 bytes status (assuming int32)
//       throw IpcParsingException('Received data length (${data.lengthInBytes}) is less than expected MasterMessage size (5)');
//     }
//     final byteData = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
//     final clientId = byteData.getUint8(0);
//     final status = byteData.getInt32(1, Endian.little); // Assuming int is 32-bit little endian
//     return MasterMessage(clientId, status);
//   }
// }

// --- lib/data/models/display_data.dart ---
import 'dart:io';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../../core/constants/ipc_constants.dart'; // Make sure this path is correct
import '../../core/error/exceptions.dart';     // Make sure this path is correct

// Assume these constants are defined elsewhere (e.g., in ipc_constants.dart)
// const int displayDataStructSize = 42; // 5*u32 + 4*float + 6*u8 = 20 + 16 + 6 = 42
// const int maxTopicNameLength = 64;

// Enums matching C code (optional but good for clarity)
// Ensure these match the integer values used in the C code exactly.
enum DriveMode { comfort, power, sprint, reverse } // Assumes 0, 1, 2, 3
enum AbsStatus { normal, warning, error }         // Assumes 0, 1, 2

class DisplayData extends Equatable {
  final int bmsErrors;      // uint32_t
  final int mcuErrors;      // uint32_t
  final int obcErrors;      // uint32_t
  final int plcErrors;      // uint32_t
  final int vcuErrors;      // uint32_t
  final double batteryTemp; // float
  final double throttle;    // float
  final double speed;       // float
  final double batterySoc;  // float
  final AbsStatus absStatus;// uint8_t -> enum
  final DriveMode driveMode;// uint8_t -> enum
  // DPad bit flags (from uint8_t)
  final bool dpadBottom;
  final bool dpadRight;
  final bool dpadUp;
  final bool dpadLeft;
  // Other flags (from uint8_t)
  final bool killSwitch;    // uint8_t (0 or 1)
  final bool highBeam;      // uint8_t (0 or 1)
  // Indicator bit flags (from uint8_t)
  final bool indicatorRight;
  final bool indicatorLeft;

  const DisplayData({
    required this.bmsErrors,
    required this.mcuErrors,
    required this.obcErrors,
    required this.plcErrors,
    required this.vcuErrors,
    required this.batteryTemp,
    required this.throttle,
    required this.speed,
    required this.batterySoc,
    required this.absStatus,
    required this.driveMode,
    required this.dpadBottom,
    required this.dpadRight,
    required this.dpadUp,
    required this.dpadLeft,
    required this.killSwitch,
    required this.highBeam,
    required this.indicatorRight,
    required this.indicatorLeft,
  });

  // Factory constructor to parse from raw bytes
  factory DisplayData.fromBytes(Uint8List data) {
    // *** CRITICAL: Ensure displayDataStructSize matches the C struct size ***
    if (data.lengthInBytes < displayDataStructSize) {
      throw IpcParsingException(
          'Received data length (${data.lengthInBytes}) is less than expected DisplayData size ($displayDataStructSize)');
    }
    // Optionally, check if length is *exactly* displayDataStructSize if no extra data is expected
    // if (data.lengthInBytes != displayDataStructSize) {
    //    print("IPC Warning: Received data length (${data.lengthInBytes}) != expected size ($displayDataStructSize)");
    // }

    // Use ByteData for structured access.
    // *** CRITICAL: Assumes Little Endian byte order. MUST match the C side. ***
    final byteData = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    int offset = 0;

    try {
      // Read uint32_t values (4 bytes each)
      // Add offset checks for extra safety (optional but good for debugging)
      // if (offset + 4 > data.lengthInBytes) throw IpcParsingException('Buffer underflow reading bmsErrors');
      final bmsErrors = byteData.getUint32(offset, Endian.little);
      offset += 4;
      final mcuErrors = byteData.getUint32(offset, Endian.little);
      offset += 4;
      final obcErrors = byteData.getUint32(offset, Endian.little);
      offset += 4;
      final plcErrors = byteData.getUint32(offset, Endian.little);
      offset += 4;
      final vcuErrors = byteData.getUint32(offset, Endian.little);
      offset += 4; // offset = 20

      // Read float values (4 bytes each)
      final batteryTemp = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final throttle = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final speed = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final batterySoc = byteData.getFloat32(offset, Endian.little);
      offset += 4; // offset = 36

      // Read uint8_t values (1 byte each)
      final absStatusRaw = byteData.getUint8(offset);
      offset += 1;
      final driveModeRaw = byteData.getUint8(offset);
      offset += 1;
      final dpadRaw = byteData.getUint8(offset);
      offset += 1;
      final killswRaw = byteData.getUint8(offset);
      offset += 1;
      final highbeamRaw = byteData.getUint8(offset);
      offset += 1;
      final indicatorsRaw = byteData.getUint8(offset);
      offset += 1; // offset = 42 (should match displayDataStructSize)

      // if (offset != displayDataStructSize) {
      //     print("IPC Warning: Offset ($offset) after parsing does not match expected size ($displayDataStructSize)");
      // }

      // --- Convert raw values to Dart types/enums ---

      // Enums: Use clamp to prevent RangeError if C sends an invalid value
      final absStatus = AbsStatus.values[absStatusRaw.clamp(0, AbsStatus.values.length - 1)];
      final driveMode = DriveMode.values[driveModeRaw.clamp(0, DriveMode.values.length - 1)];
      // Optional: Log a warning if clamping occurred
      // if (absStatusRaw >= AbsStatus.values.length) print("Warning: Clamped invalid absStatus $absStatusRaw");
      // if (driveModeRaw >= DriveMode.values.length) print("Warning: Clamped invalid driveMode $driveModeRaw");


      // Parse bitfields - Ensure masks match the C struct definition precisely
      // DPad: 0 0 0 0 BOTTOM RIGHT UP LEFT (Example - verify this layout!)
      const int dpadLeftMask   = 0x01; // Bit 0
      const int dpadUpMask     = 0x02; // Bit 1
      const int dpadRightMask  = 0x04; // Bit 2
      const int dpadBottomMask = 0x08; // Bit 3
      final dpadLeft   = (dpadRaw & dpadLeftMask) != 0;
      final dpadUp     = (dpadRaw & dpadUpMask) != 0;
      final dpadRight  = (dpadRaw & dpadRightMask) != 0;
      final dpadBottom = (dpadRaw & dpadBottomMask) != 0;


      // Simple boolean flags (assuming 0 = false, non-zero = true)
      final killSwitch = killswRaw != 0;
      final highBeam = highbeamRaw != 0;

      // Indicators: 0 0 0 0 0 0 RIGHT LEFT (Example - verify this layout!)
      const int indLeftMask  = 0x01; // Bit 0
      const int indRightMask = 0x02; // Bit 1
      final indicatorLeft  = (indicatorsRaw & indLeftMask) != 0;
      final indicatorRight = (indicatorsRaw & indRightMask) != 0;

      return DisplayData(
        bmsErrors: bmsErrors,
        mcuErrors: mcuErrors,
        obcErrors: obcErrors,
        plcErrors: plcErrors,
        vcuErrors: vcuErrors,
        batteryTemp: batteryTemp,
        throttle: throttle,
        speed: speed,
        batterySoc: batterySoc,
        absStatus: absStatus,
        driveMode: driveMode,
        dpadBottom: dpadBottom,
        dpadRight: dpadRight,
        dpadUp: dpadUp,
        dpadLeft: dpadLeft,
        killSwitch: killSwitch,
        highBeam: highBeam,
        indicatorRight: indicatorRight,
        indicatorLeft: indicatorLeft,
      );
    } catch (e) {
      // Catch potential RangeErrors from getXXX methods if offset is wrong, or other errors
      // Re-wrap as a specific parsing exception
      throw IpcParsingException('Error parsing DisplayData bytes at offset $offset: $e', originalException: e);
    }
  }

  @override
  List<Object?> get props => [
    bmsErrors, mcuErrors, obcErrors, plcErrors, vcuErrors,
    batteryTemp, throttle, speed, batterySoc,
    absStatus, driveMode,
    dpadBottom, dpadRight, dpadUp, dpadLeft,
    killSwitch, highBeam,
    indicatorRight, indicatorLeft,
  ];

  @override
  // Make toString more readable for debugging
  String toString() {
    return 'DisplayData('
        'Errors(BMS:$bmsErrors MCU:$mcuErrors OBC:$obcErrors PLC:$plcErrors VCU:$vcuErrors), '
        'Temp:${batteryTemp.toStringAsFixed(1)}C, Thr:${throttle.toStringAsFixed(2)}, '
        'Spd:${speed.toStringAsFixed(1)}km/h, SOC:${batterySoc.toStringAsFixed(1)}%, '
        'ABS:$absStatus, Mode:$driveMode, Kill:$killSwitch, HB:$highBeam, '
        'DPad(L:$dpadLeft U:$dpadUp R:$dpadRight B:$dpadBottom), '
        'Ind(L:$indicatorLeft R:$indicatorRight)'
        ')';
  }
}


// --- Helper Functions (Potentially in a separate file or ipc_helpers.dart) ---

// Helper function to serialize ClientMessage (used by IpcService)
// Corresponds to C struct:
// typedef struct ClientMessage {
//   uint8_t  request_type;
//   uint8_t  client_id;        // Sender's ID (0 during registration)
//   char     topic_name[64];   // Null-terminated
//   uint16_t data_size;        // Size of data field (usually 0 for reg/sub/unsub)
//   uint8_t  data[MAX_DATA_SIZE]; // Not used for reg/sub/unsub requests
// } ClientMessage;
// *** Ensure maxTopicNameLength matches C definition ***
Uint8List serializeClientMessage({
  required int requestType,
  int clientId = 0, // Use 0 when registering, actual ID otherwise
  String topicName = "",
  // data and data_size are omitted as they are 0 for reg/sub/unsub requests
}) {
  final builder = BytesBuilder();

  // request_type (uint8_t)
  builder.addByte(requestType);

  // client_id (uint8_t)
  builder.addByte(clientId);

  // topic_name (char[maxTopicNameLength]) - null-padded ASCII/UTF-8
  List<int> topicBytes = List.filled(maxTopicNameLength, 0); // Initialize with null bytes
  // Encode string to bytes (UTF-8 is often compatible with ASCII for simple names)
  List<int> nameBytes = SystemEncoding().encode(topicName); // Use system encoding or explicit UTF8/ASCII
  // Clamp length to avoid overflow, ensure null termination
  int lenToCopy = nameBytes.length < (maxTopicNameLength - 1) ? nameBytes.length : (maxTopicNameLength - 1);
  topicBytes.setRange(0, lenToCopy, nameBytes);
  // Ensure null termination even if topicName was exactly maxTopicNameLength-1
  topicBytes[maxTopicNameLength - 1] = 0;
  builder.add(topicBytes);

  // data_size (uint16_t) - Little Endian
  // Always 0 for reg/sub/unsub requests in this design
  final sizeData = ByteData(2)..setUint16(0, 0, Endian.little);
  builder.add(sizeData.buffer.asUint8List());

  // data[MAX_DATA_SIZE] - Omitted as data_size is 0

  // Final message size should be 1 + 1 + maxTopicNameLength + 2
  final message = builder.toBytes();
  // print("DEBUG: Serialized ClientMessage: Type=$requestType, ID=$clientId, Topic='$topicName', Size=${message.length}");
  return message;
}

// Helper class to parse MasterMessage
// Corresponds to C struct:
// typedef struct MasterMessage {
//   uint8_t client_id; // Client ID assigned (in registration response) or relevant client (ignored otherwise?)
//   int     status;    // Status code (e.g., 0 for success, negative for errors). Use fixed size like int32_t in C.
// } MasterMessage;
// *** Ensure size of 'int' (status) matches the C definition (e.g., int32_t = 4 bytes) ***
class MasterMessage {
  final int clientId;
  final int status; // Assuming matches int32_t from C

  // Expected size: 1 byte (clientId) + 4 bytes (status) = 5 bytes
  static const int expectedSize = 5;

  MasterMessage(this.clientId, this.status);

  factory MasterMessage.fromBytes(Uint8List data) {
    if (data.lengthInBytes < expectedSize) {
      throw IpcParsingException(
          'Received data length (${data.lengthInBytes}) is less than expected MasterMessage size ($expectedSize)');
    }

    // *** CRITICAL: Assumes Little Endian byte order. MUST match the C side. ***
    final byteData = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    final clientId = byteData.getUint8(0);
    // Assuming 'int' status in C is int32_t
    final status = byteData.getInt32(1, Endian.little);
    return MasterMessage(clientId, status);
  }

  @override
  String toString() {
    return 'MasterMessage(clientId: $clientId, status: $status)';
  }
}


