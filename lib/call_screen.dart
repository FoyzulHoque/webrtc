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

  static const String _clientToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjY4ODY3NzEwZmJhMTU1NWY5NDJjMzkwMiIsImVtYWlsIjoicmFmc2Fuc2F5ZWQxMzJAZ21haWwuY29tIiwicm9sZSI6IkNsaWVudCIsImlhdCI6MTc1MzczMzU5MCwiZXhwIjoxNzg1MjY5NTkwfQ.4Pxb5QGobQuji-dbxFsQZB6cswMkpXtcs4CRCv2fuFg';

  static const String _hostToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjY4NzZlYTcxZTg0MjRlNjNlMjZhNGMxMiIsImVtYWlsIjoiZWxlZ2FuY2VzaGFqZ2hvckBnbWFpbC5jb20iLCJyb2xlIjoiSG9zdCIsImlhdCI6MTc1MzczMzY1NCwiZXhwIjoxNzg1MjY5NjU0fQ.iChokMd65b1cv6cV94jOsaPJy-e1wDyUMpC65IXSJLw';

  static const String _hostId = '6876ea71e8424e63e26a4c12';
  static const String _clientId = '68867710fba1555f942c3902';

  @override
  void dispose() {
    super.dispose();
  }

  void _fillForHostRole() {
    controller.tokenController.text = _clientToken;
    controller.peerIdController.text = _hostId;
    Get.snackbar('Filled', 'Using Host role (client token + host id)');
  }

  void _fillForClientRole() {
    controller.tokenController.text = _hostToken;
    controller.peerIdController.text = _clientId;
    Get.snackbar('Filled', 'Using Client role (host token + client id)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC Call')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ---- Role Quick-Fill Buttons ----
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person),
                    label: const Text('Host'),
                    onPressed: _fillForHostRole,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Client'),
                    onPressed: _fillForClientRole,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Input fields
            TextField(
              controller: controller.tokenController,
              decoration: const InputDecoration(labelText: 'My Token'),
              maxLines: 3,
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
