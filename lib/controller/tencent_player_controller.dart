import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tencentplayer_plus/flutter_tencentplayer_plus.dart';

class TencentPlayerController extends ValueNotifier<TencentPlayerValue> {
  int _textureId;
  final String dataSource;
  final DataSourceType dataSourceType;
  final PlayerConfig playerConfig;

  MethodChannel channel = TencentPlayer.channel;

  TencentPlayerController.asset(this.dataSource,
      {this.playerConfig = const PlayerConfig()})
      : dataSourceType = DataSourceType.asset,
        super(TencentPlayerValue());

  TencentPlayerController.network(this.dataSource,
      {this.playerConfig = const PlayerConfig()})
      : dataSourceType = DataSourceType.network,
        super(TencentPlayerValue());

  TencentPlayerController.file(String filePath,
      {this.playerConfig = const PlayerConfig()})
      : dataSource = filePath,
        dataSourceType = DataSourceType.file,
        super(TencentPlayerValue());

  bool _isDisposed = false;
  StreamSubscription<dynamic> _eventSubscription;
  _VideoAppLifeCycleObserver _lifeCycleObserver;

//  @visibleForTesting
  int get textureId => _textureId;

  ///初始化播放器的方法
  Future<void> initialize() async {
    _lifeCycleObserver = _VideoAppLifeCycleObserver(this);
    _lifeCycleObserver.initialize();
    Map<dynamic, dynamic> dataSourceDescription;
    switch (dataSourceType) {
      case DataSourceType.asset:
        dataSourceDescription = <String, dynamic>{'asset': dataSource};
        break;
      case DataSourceType.network:
      case DataSourceType.file:
        dataSourceDescription = <String, dynamic>{'uri': dataSource};
        break;
    }

    value = value.copyWith(isPlaying: playerConfig.autoPlay);

    // set default fullScreen value
    value = value.copyWith(isFullScreen: playerConfig.isMuted ?? false);
    value = value.copyWith(isMuted: playerConfig.isMuted ?? false);

    dataSourceDescription.addAll(playerConfig.toJson());

    final Map<String, dynamic> response =
        await channel.invokeMapMethod<String, dynamic>(
      'create',
      dataSourceDescription,
    );

    _textureId = response['textureId'];

    ///设置监听naive 返回的的数据
    _eventSubscription = _eventChannelFor(_textureId)
        .receiveBroadcastStream()
        .listen(eventListener);
  }

  ///注册监听native的方法
  EventChannel _eventChannelFor(int textureId) {
    return EventChannel('flutter_tencentplayer/videoEvents$textureId');
  }

  ///native 传递到flutter 进行数据处理
  void eventListener(dynamic event) {
    if (_isDisposed) {
      return;
    }
    final Map<dynamic, dynamic> map = event;
    switch (map['event']) {
      case 'initialized':
        value = value.copyWith(
          duration: Duration(milliseconds: map['duration']),
          size: Size(map['width']?.toDouble() ?? 0.0,
              map['height']?.toDouble() ?? 0.0),
        );
        break;
      case 'progress':
        value = value.copyWith(
          position: Duration(milliseconds: map['progress']),
          duration: Duration(milliseconds: map['duration']),
          playable: Duration(milliseconds: map['playable']),
        );
        break;
      case 'loading':
        value = value.copyWith(isLoading: true);
        break;
      case 'loadingend':
        value = value.copyWith(isLoading: false);
        break;
      case 'playend':
        value = value.copyWith(isPlaying: false, position: value.duration);
        break;
      case 'netStatus':
        value = value.copyWith(netSpeed: map['netSpeed']);
        break;
      case 'error':
        value = value.copyWith(errorDescription: map['errorInfo']);
        break;
    }
  }

  @override
  Future dispose() async {
    if (!_isDisposed) {
      _isDisposed = true;
      await _eventSubscription?.cancel();
      await channel.invokeListMethod(
          'dispose', <String, dynamic>{'textureId': _textureId});
      _lifeCycleObserver.dispose();
    }
    super.dispose();
  }

  Future<void> enterfullScreen() async {
    value = value.copyWith(isFullScreen: true);
  }

  Future<void> exitFullScreen() async {
    value = value.copyWith(isFullScreen: false);
  }

  Future<void> toggleFullScreen() {
    value = value.copyWith(isFullScreen: !value.isFullScreen);
  }

  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
    await _applyPlayPause();
  }

  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
    await _applyPlayPause();
  }

  Future<void> _applyPlayPause() async {
    if (!value.initialized || _isDisposed) {
      return;
    }
    if (value.isPlaying) {
      await channel
          .invokeMethod('play', <String, dynamic>{'textureId': _textureId});
    } else {
      await channel
          .invokeMethod('pause', <String, dynamic>{'textureId': _textureId});
    }
  }

  Future<void> seekTo(Duration moment) async {
    if (_isDisposed) {
      return;
    }
    if (moment == null) {
      return;
    }
    if (moment > value.duration) {
      moment = value.duration;
    } else if (moment < const Duration()) {
      moment = const Duration();
    }
    await channel.invokeMethod('seekTo', <String, dynamic>{
      'textureId': _textureId,
      'location': moment.inSeconds,
    });
    value = value.copyWith(position: moment);
  }

  ///点播为m3u8子流，会自动无缝seek
  Future<void> setBitrateIndex(int index) async {
    if (_isDisposed) {
      return;
    }
    await channel.invokeMethod('setBitrateIndex', <String, dynamic>{
      'textureId': _textureId,
      'index': index,
    });
    value = value.copyWith(bitrateIndex: index);
  }

  Future<void> setRate(double rate) async {
    if (_isDisposed) {
      return;
    }
    if (rate > 2.0) {
      rate = 2.0;
    } else if (rate < 1.0) {
      rate = 1.0;
    }
    await channel.invokeMethod('setRate', <String, dynamic>{
      'textureId': _textureId,
      'rate': rate,
    });
    value = value.copyWith(rate: rate);
  }

  Future<void> setMute(bool isMuted) async {
    if (_isDisposed) {
      return;
    }
    if (isMuted == null) {
      return;
    }
    await channel.invokeMethod('setMute', <String, dynamic>{
      'textureId': _textureId,
      'isMuted': isMuted,
    });
    value = value.copyWith(isMuted: isMuted);
  }
}

///视频组件生命周期监听
class _VideoAppLifeCycleObserver with WidgetsBindingObserver {
  bool _wasPlayingBeforePause = false;
  final TencentPlayerController _controller;

  _VideoAppLifeCycleObserver(this._controller);

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {

      ///组件进入暂停状态
      case AppLifecycleState.paused:
        _wasPlayingBeforePause = _controller.value.isPlaying;
        _controller.pause();
        break;

      ///组件进入活跃状态
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause) {
          _controller.play();
        }
        break;
      default:
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
