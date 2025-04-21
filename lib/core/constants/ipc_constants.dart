// // lib/core/constants/ipc_constants.dart
// import 'dart:io';
//
// // Paths
// const String ipcMasterPath = "/tmp/ipc_master";
// const String ipcClientDefaultPath = "/tmp/client";
// String clientSpecificPath(int clientId) => "/tmp/$clientId";
// String clientTopicPath(int clientId, String topicName) => "/tmp/$clientId-$topicName";
//
// const int ipcRegisterClient = 0;
// const int ipcRegisterSubscriber = 1;
// const int ipcDeregisterSubscriber = 2;
// // const int ipcPublishMessage = 3;
//
// // Data Limits / Sizes
// const int maxTopicNameLength = 64; // Assumed from C struct
// const int maxDataSize = 1024;
//
// // Data Structures Sizes (Important for parsing)
// // Based on DisplayData struct:
// // 5 * uint32_t (errors) = 5 * 4 = 20 bytes
// // 4 * float (battery_temp, throttle, speed, battery_soc) = 4 * 4 = 16 bytes
// // 5 * uint8_t (abs_status, drivemode, dpad, killsw, highbeam, indicators) = 6 bytes
// // Total = 20 + 16 + 6 = 42 bytes
// const int displayDataStructSize = 42;
//
// // Topic Name
// const String displayDataTopic = "DisplayData";
//
// // Socket address family for Unix sockets
// final InternetAddressType unixAddressType = InternetAddressType.unix;




// --- Define Constants (ipc_constants.dart or similar) ---
// Socket Paths
const String ipcMasterPath = '/tmp/ipc_master';
const String ipcClientDefaultPath = '/tmp/client'; // Default path for initial contact

// Topic Names (must match master)
const String displayDataTopic = 'DisplayData';

// Function to generate client-specific paths
String clientSpecificPath(int clientId) => '/tmp/$clientId';
String clientTopicPath(int clientId, String topic) => '/tmp/$clientId-$topic';

// Request Types (must match master)
const int ipcRegisterClient = 1;
const int ipcRegisterSubscriber = 2;
const int ipcDeregisterSubscriber = 3;
// Add others if needed (e.g., IPC_KEEPALIVE = 4;)

// Data Structure Sizes (must match C structs)
const int displayDataStructSize = 42; // 5*u32 + 4*float + 6*u8 = 20 + 16 + 6 = 42
const int maxTopicNameLength = 64;   // Including null terminator space
