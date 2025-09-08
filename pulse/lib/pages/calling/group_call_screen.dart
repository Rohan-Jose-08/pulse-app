import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../backend/webrtc_group_call_service.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen(
      {super.key, required this.conversationId, this.isVideo = true});
  final String conversationId;
  final bool isVideo;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final svc = GroupCallService.instance;
  List<String> _participants = [];

  @override
  void initState() {
    super.initState();
    svc.attachSocketListeners();
    svc.initRenderers();
    svc.start(conversationId: widget.conversationId, isVideo: widget.isVideo);
    // Auto-join; UI presents leave button
    Future.microtask(() => svc.join());
    svc.participantsStream.listen((list) {
      if (!mounted) return;
      setState(() => _participants = List<String>.from(list));
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: t.primaryBackground,
      appBar: AppBar(
        title: const Text('Group Call'),
        backgroundColor: t.secondaryBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            onPressed: () async {
              await svc.leave();
              if (mounted) Navigator.of(context).maybePop();
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(12),
              children: [
                _tile('You', svc.localRenderer),
                for (final uid in _participants) _remoteTile(uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, RTCVideoRenderer renderer) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        Container(
            color: Colors.black54,
            child: RTCVideoView(renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: true)),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        )
      ]),
    );
  }

  Widget _remoteTile(String userId) {
    final r = svc.remoteRendererFor(userId);
    if (r == null) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return _tile(userId, r);
  }
}
