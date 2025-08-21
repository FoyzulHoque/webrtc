import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_controller.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallController controller = Get.put(CallController());

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC Call')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Input fields
            TextField(
              controller: controller.tokenController,
              decoration: const InputDecoration(labelText: 'My Token'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.peerIdController,
              decoration: const InputDecoration(labelText: 'Peer User ID'),
            ),
            const SizedBox(height: 12),

            // Connect button
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final token = controller.tokenController.text.trim();
                      final peerId = controller.peerIdController.text.trim();
                      if (token.isEmpty || peerId.isEmpty) {
                        Get.snackbar('Error', 'Enter token & peer ID');
                        return;
                      }
                      controller.connectWebSocket();
                    },
                    child: const Text('Connect'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Call buttons
            Obx(() {
              return controller.inCall.value
                  ? ElevatedButton(
                      onPressed: controller.endCall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('End Call'),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => controller.startCall(video: false),
                            child: const Text('Audio Call'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => controller.startCall(video: true),
                            child: const Text('Video Call'),
                          ),
                        ),
                      ],
                    );
            }),

            const SizedBox(height: 20),

            // Local video
            SizedBox(
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: controller.localRenderer.srcObject != null
                    ? RTCVideoView(controller.localRenderer, mirror: true)
                    : Container(
                        color: Colors.black12,
                        child: const Center(child: Text('Local video')),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // Remote video
            SizedBox(
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: controller.remoteRenderer.srcObject != null
                    ? RTCVideoView(controller.remoteRenderer)
                    : Container(
                        color: Colors.black12,
                        child: const Center(child: Text('Remote video')),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // Status text
            Obx(
              () => Text(
                controller.statusText.value,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
