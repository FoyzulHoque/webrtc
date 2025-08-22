import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:flutter/material.dart';
import 'package:webrtc/urls.dart';

const String kWsUrl =
    SignalingConstants.wsUrl; // keep your constant if you have it

class CallController extends GetxController {
  IOWebSocketChannel? _channel;

  final localRenderer = webrtc.RTCVideoRenderer();
  final remoteRenderer = webrtc.RTCVideoRenderer();
  webrtc.RTCPeerConnection? _pc;

  webrtc.MediaStream? _localStream;

  final inCall = false.obs;
  final isRinging = false.obs;
  final isIncoming = false.obs;
  final statusText = 'Idle'.obs;
  RxBool isLocalStreamReady = false.obs;
  RxBool isRemoteStreamReady = false.obs;

  final tokenController = TextEditingController();
  final peerIdController = TextEditingController();

  String? _myUserId;
  Map<String, dynamic>? _incomingCallData;
  Timer? _ringingTimeout;

  @override
  void onInit() {
    super.onInit();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  /// -------------------- WebSocket --------------------
  void connectWebSocket() {
    if (_channel != null) return;

    _channel = IOWebSocketChannel.connect(Uri.parse(kWsUrl));

    statusText.value = 'Connecting WS...';

    _channel!.stream.listen(
      _onWsMessage,
      onError: (e, st) {
        statusText.value = 'WS Error: $e';
        _cleanupWs();
      },
      onDone: () {
        statusText.value = 'WS Closed';
        _cleanupWs();
      },
    );

    final token = tokenController.text.trim();
    _sendWs({'event': 'authenticate', 'token': token});
  }

  void _sendWs(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _onWsMessage(dynamic message) async {
    Map<String, dynamic> data;
    try {
      data = (message is String)
          ? jsonDecode(message)
          : Map<String, dynamic>.from(message);
    } catch (e) {
      statusText.value = 'Bad WS message';
      return;
    }

    final event = data['event'];
    switch (event) {
      case 'authenticated':
        _myUserId = data['data']?['userId']?.toString();
        statusText.value = 'Authenticated as $_myUserId';
        break;

      case 'incomingCall':
        _incomingCallData = Map<String, dynamic>.from(data['data'] ?? {});
        isRinging.value = true;
        isIncoming.value = true;

        _showIncomingDialog(
          fromUserId: _incomingCallData!['fromUserId'].toString(),
          callType: _incomingCallData!['callType']?.toString() ?? 'audio',
        );

        _ringingTimeout?.cancel();
        _ringingTimeout = Timer(const Duration(seconds: 30), () {
          if (!inCall.value)
            rejectCall(_incomingCallData!['fromUserId'].toString());
        });
        break;

      case 'callAnswered':
        final answer = data['data']?['answer'];
        if (_pc != null && answer != null) {
          await _pc!.setRemoteDescription(
            webrtc.RTCSessionDescription(
              answer['sdp'] as String,
              answer['type'] as String,
            ),
          );
          statusText.value = 'Call connected';
        }
        break;

      case 'iceCandidate':
        final c = data['data']?['candidate'];
        if (_pc != null && c != null) {
          try {
            await _pc!.addCandidate(
              webrtc.RTCIceCandidate(
                c['candidate'] as String?,
                c['sdpMid'] as String?,
                (c['sdpMLineIndex'] is int)
                    ? c['sdpMLineIndex'] as int
                    : (c['sdpMLineIndex'] as num?)?.toInt(),
              ),
            );
          } catch (_) {}
        }
        break;

      case 'callDisconnected':
        _endCallInternal();
        break;

      default:
        break;
    }
  }

  void _showIncomingDialog({
    required String fromUserId,
    required String callType,
  }) {
    if (Get.isDialogOpen == true) return;
    Get.defaultDialog(
      title: 'Incoming ${callType.toUpperCase()} Call',
      middleText: 'From: $fromUserId',
      barrierDismissible: false,
      confirm: ElevatedButton(
        onPressed: () async {
          await acceptCall();
          if (Get.isDialogOpen == true) Get.back();
        },
        child: const Text('Accept'),
      ),
      cancel: ElevatedButton(
        onPressed: () {
          rejectCall(fromUserId);
          if (Get.isDialogOpen == true) Get.back();
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        child: const Text('Reject'),
      ),
    );
  }

  /// -------------------- Permissions --------------------
  Future<bool> _requestPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    return (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
  }

  /// -------------------- Call Flow --------------------
  Future<void> startCall({required bool video}) async {
    if (_channel == null) {
      Get.snackbar('WebSocket', 'Please connect first');
      return;
    }
    if (peerIdController.text.trim().isEmpty) {
      Get.snackbar('Error', 'Please enter peer user ID');
      return;
    }

    if (!await _requestPermissions()) {
      Get.snackbar('Permissions', 'Camera and Microphone are required');
      return;
    }

    await _createPeerConnection(video: video);
    if (_pc == null) return;

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    _sendWs({
      'event': 'callUser',
      'toUserId': peerIdController.text.trim(),
      'callType': video ? 'video' : 'audio',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });

    inCall.value = true;
    statusText.value = 'Calling...';
  }

  Future<void> acceptCall() async {
    if (_incomingCallData == null) return;

    isRinging.value = false;
    isIncoming.value = false;
    _ringingTimeout?.cancel();

    final callType = _incomingCallData!['callType']?.toString() == 'video';
    await _createPeerConnection(video: callType);
    if (_pc == null) return;

    final offer = _incomingCallData!['offer'];
    await _pc!.setRemoteDescription(
      webrtc.RTCSessionDescription(
        offer['sdp'] as String,
        offer['type'] as String,
      ),
    );

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    _sendWs({
      'event': 'answerCall',
      'toUserId': _incomingCallData!['fromUserId'],
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });

    inCall.value = true;
    statusText.value = 'In call';
  }

  void rejectCall(String fromUserId) {
    _sendWs({'event': 'disconnectCall', 'toUserId': fromUserId});
    isRinging.value = false;
    isIncoming.value = false;
    _ringingTimeout?.cancel();
    Get.snackbar('Call', 'Call rejected');
  }

  /// -------------------- Peer Connection --------------------
  Future<void> _createPeerConnection({required bool video}) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _pc = await webrtc.createPeerConnection(config);

    // Local stream
    try {
      final constraints = <String, dynamic>{
        'audio': true,
        'video': video
            ? {
                'facingMode': 'user',
                'width': 640,
                'height': 480,
                'frameRate': 30,
              }
            : false,
      };
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia(
        constraints,
      );
      localRenderer.srcObject = _localStream;
      isLocalStreamReady.value = true; // Set flag when stream is ready

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      print(
        '[Local Stream] Tracks: ${_localStream!.getTracks().map((t) => t.kind).toList()}',
      );
    } catch (e) {
      Get.snackbar('Media Error', 'Failed to access camera/microphone.');
      await _pc?.close();
      _pc = null;
      return;
    }
    // Remote stream
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        isRemoteStreamReady.value = true; // Mark remote stream as ready
        print(
          '[Remote Stream] Tracks: ${event.streams.first.getTracks().map((t) => t.kind).toList()}',
        );
      }
    };

    // ICE
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;

      final toUserId = peerIdController.text.trim().isNotEmpty
          ? peerIdController.text.trim()
          : _incomingCallData?['fromUserId']?.toString();
      if (toUserId == null) return;

      _sendWs({
        'event': 'iceCandidate',
        'toUserId': toUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'sdpMid': candidate.sdpMid,
        },
      });
    };

    _pc!.onIceConnectionState = (state) {
      if (state ==
              webrtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == webrtc.RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _endCallInternal();
      }
    };
  }

  void endCall() {
    final toUserId = peerIdController.text.trim().isNotEmpty
        ? peerIdController.text.trim()
        : _incomingCallData?['fromUserId']?.toString();
    if (toUserId != null)
      _sendWs({'event': 'disconnectCall', 'toUserId': toUserId});
    _endCallInternal();
  }

  void _endCallInternal() {
    inCall.value = false;
    isRinging.value = false;
    isIncoming.value = false;

    _pc?.onIceCandidate = null;
    _pc?.onTrack = null;
    _pc?.close();
    _pc = null;

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    statusText.value = 'Call ended';
  }

  void _cleanupWs() {
    try {
      _channel?.sink.close(ws_status.goingAway);
    } catch (_) {}
    _channel = null;
  }

  @override
  void onClose() {
    _cleanupWs();
    _ringingTimeout?.cancel();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _endCallInternal();
    super.onClose();
  }
}
