import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tencentplayer_plus/flutter_tencentplayer_plus.dart';

class DownloadController extends ValueNotifier<Map<String, DownloadValue>> {
  final String savePath;
  final int appId;
  StreamSubscription<dynamic> _eventSubscription;
  MethodChannel channel = TencentPlayer.channel;
  bool _isDisposed = false;

  DownloadController(this.savePath, {this.appId})
      : super(Map<String, DownloadValue>());

  void dowload(String urlOrFileId, {int quanlity}) async {
    Map<dynamic, dynamic> downloadInfoMap = {
      "savePath": savePath,
      "urlOrFileId": urlOrFileId,
      "appId": appId,
      "quanlity": quanlity,
    };

    await channel.invokeMethod(
      'download',
      downloadInfoMap,
    );
    _eventSubscription = _eventChannelFor(urlOrFileId)
        .receiveBroadcastStream()
        .listen(eventListener);
  }

  EventChannel _eventChannelFor(String urlOrFileId) {
    return EventChannel('flutter_tencentplayer/downloadEvents$urlOrFileId');
  }

  void eventListener(dynamic event) {
    if (_isDisposed) {
      return;
    }
    final Map<dynamic, dynamic> map = event;
    debugPrint("native to flutter");
    debugPrint(map.toString());
    DownloadValue downloadValue = DownloadValue.fromJson(map);
    if (downloadValue.fileId != null) {
      value[downloadValue.fileId] = downloadValue;
    } else {
      value[downloadValue.url] = downloadValue;
    }
    notifyListeners();
  }

  @override
  Future dispose() async {
    _isDisposed = true;
    _eventSubscription.cancel();
    super.dispose();
  }

  Future pauseDownload(String urlOrFileId) async {
    if (_isDisposed) {
      return;
    }
    await channel.invokeMethod(
      'stopDownload',
      {
        "urlOrFileId": urlOrFileId,
      },
    );
  }

  Future cancelDownload(String urlOrFileId) async {
    if (_isDisposed) {
      return;
    }
    await channel.invokeMethod(
      'stopDownload',
      {
        "urlOrFileId": urlOrFileId,
      },
    );

    if (value.containsKey(urlOrFileId)) {
      Future.delayed(Duration(milliseconds: 2500), () {
        value.remove(urlOrFileId);
      });
    }

    notifyListeners();
  }
}
