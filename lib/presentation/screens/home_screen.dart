// lib/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/display_data.dart';
import '../bloc/ipc_bloc.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Unix Socket IPC'),
      ),
      body: BlocBuilder<IpcBloc, IpcState>(
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusIndicator(context, state),
                const SizedBox(height: 20),
                if (state is IpcConnected)
                  _buildDataDisplay(context, state.latestData)
                else if (state is IpcConnecting)
                  const Center(child: CircularProgressIndicator())
                else if (state is IpcError)
                    Center(child: Text('Error: ${state.message}', style: const TextStyle(color: Colors.red)))
                  else if (state is IpcDisconnected)
                      Center(child: Text('Disconnected. ${state.reason ?? ""}'))
                    else // IpcInitial
                      const Center(child: Text('Press "Connect" to start.')),

                const Spacer(), // Push buttons to bottom
                _buildActionButtons(context, state),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context, IpcState state) {
    String statusText;
    Color statusColor;

    if (state is IpcConnected) {
      statusText = 'Connected';
      statusColor = Colors.green;
    } else if (state is IpcConnecting) {
      statusText = 'Connecting...';
      statusColor = Colors.orange;
    } else if (state is IpcError) {
      statusText = 'Error';
      statusColor = Colors.red;
    } else { // IpcInitial, IpcDisconnected
      statusText = 'Disconnected';
      statusColor = Colors.grey;
    }

    return Row(
      children: [
        Text('Status: ', style: Theme.of(context).textTheme.titleMedium),
        Text(
          statusText,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: statusColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, IpcState state) {
    bool canConnect = state is IpcInitial || state is IpcDisconnected || state is IpcError;
    bool canDisconnect = state is IpcConnecting || state is IpcConnected;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton(
          onPressed: canConnect
              ? () => context.read<IpcBloc>().add(ConnectIpc())
              : null,
          child: const Text('Connect'),
        ),
        ElevatedButton(
          onPressed: canDisconnect
              ? () => context.read<IpcBloc>().add(DisconnectIpc())
              : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          child: const Text('Disconnect'),
        ),
      ],
    );
  }


  Widget _buildDataDisplay(BuildContext context, DisplayData? data) {
    if (data == null) {
      return const Center(child: Text('Waiting for data...'));
    }

    // Format the data nicely
    return Expanded( // Allow scrolling if content overflows
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Latest Data:", style: Theme.of(context).textTheme.headlineSmall),
            const Divider(),
            Text("Speed: ${data.speed.toStringAsFixed(1)} km/h"),
            Text("Throttle: ${(data.throttle * 100).toStringAsFixed(1)} %"),
            Text("Battery SOC: ${data.batterySoc.toStringAsFixed(1)} %"),
            Text("Battery Temp: ${data.batteryTemp.toStringAsFixed(1)} °C"),
            const SizedBox(height: 10),
            Text("Drive Mode: ${data.driveMode.name}"),
            Text("ABS Status: ${data.absStatus.name}"),
            Text("Kill Switch: ${data.killSwitch ? 'Active' : 'Inactive'}"),
            Text("High Beam: ${data.highBeam ? 'ON' : 'OFF'}"),
            const SizedBox(height: 10),
            Text("Indicators: Left=${data.indicatorLeft}, Right=${data.indicatorRight}"),
            Text("DPad: L=${data.dpadLeft}, U=${data.dpadUp}, R=${data.dpadRight}, B=${data.dpadBottom}"),
            const SizedBox(height: 10),
            Text("Errors:", style: Theme.of(context).textTheme.titleMedium),
            Text("  BMS: 0x${data.bmsErrors.toRadixString(16)}"),
            Text("  MCU: 0x${data.mcuErrors.toRadixString(16)}"),
            Text("  OBC: 0x${data.obcErrors.toRadixString(16)}"),
            Text("  PLC: 0x${data.plcErrors.toRadixString(16)}"),
            Text("  VCU: 0x${data.vcuErrors.toRadixString(16)}"),
            const SizedBox(height: 20),
            // Raw toString for debugging
            // Text("Raw: ${data.toString()}", style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}