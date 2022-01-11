// ignore_for_file: unused_element, unused_field, unused_local_variable
import 'dart:isolate';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:device_info/device_info.dart';
import 'package:android_path_provider/android_path_provider.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:permission_handler/permission_handler.dart';

const debug = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(debug: debug);
  runApp(new MyApp());
}

class _TaskInfo {
  final String? name;
  final String? link;
  String? taskId;
  int? progress = 0;
  DownloadTaskStatus? status = DownloadTaskStatus.undefined;

  _TaskInfo({this.name, this.link});
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;

    return new MaterialApp(
      title: 'Flutter Demo',
      theme: new ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: new MyHomePage(
        title: 'Downloader',
        platform: platform,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget with WidgetsBindingObserver {
  final TargetPlatform? platform;
  MyHomePage({Key? key, this.title, this.platform}) : super(key: key);
  final String? title;

  @override
  _MyHomePageState createState() => new _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _documents = [
    {
      'name': 'Learning Android Studio',
      'link':
          'http://barbra-coco.dyndns.org/student/learning_android_studio.pdf'
    },
    {
      'name': 'Android Programming Cookbook',
      'link':
          'http://enos.itcollege.ee/~jpoial/allalaadimised/reading/Android-Programming-Cookbook.pdf'
    },
    {
      'name': 'iOS Programming Guide',
      'link':
          'http://darwinlogic.com/uploads/education/iOS_Programming_Guide.pdf'
    },
    {
      'name': 'Objective-C Programming (Pre-Course Workbook',
      'link':
          'https://www.bignerdranch.com/documents/objective-c-prereading-assignment.pdf'
    },
  ];
  final _images = [
    {
      'name': 'Arches National Park',
      'link':
          'https://upload.wikimedia.org/wikipedia/commons/6/60/The_Organ_at_Arches_National_Park_Utah_Corrected.jpg'
    },
    {
      'name': 'Canyonlands National Park',
      'link':
          'https://upload.wikimedia.org/wikipedia/commons/7/78/Canyonlands_National_Park%E2%80%A6Needles_area_%286294480744%29.jpg'
    },
    {
      'name': 'Death Valley National Park',
      'link':
          'https://upload.wikimedia.org/wikipedia/commons/b/b2/Sand_Dunes_in_Death_Valley_National_Park.jpg'
    },
    {
      'name': 'Gates of the Arctic National Park and Preserve',
      'link':
          'https://upload.wikimedia.org/wikipedia/commons/e/e4/GatesofArctic.jpg'
    }
  ];
  final _videos = [
    {'name': 'Big Buck Bunny', 'link': 'http://yasersojoodi.ir/video.mp4'},
    {'name': 'Elephant Dream', 'link': 'http://yasersojoodi.ir/video.mp4'},
    {'name': 'manchester goal', 'link': 'http://yasersojoodi.ir/video.mp4'}
  ];

  List<_TaskInfo>? _tasks;
  late bool _isLoading;
  late bool _permissionReady;
  late String _localPath;
  ReceivePort _port = ReceivePort();

  Future<bool> _checkPermission() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    if (widget.platform == TargetPlatform.android &&
        androidInfo.version.sdkInt <= 28) {
      final status = await Permission.storage.status;
      if (status != PermissionStatus.granted) {
        final result = await Permission.storage.request();
        if (result == PermissionStatus.granted) {
          return true;
        }
      } else {
        return true;
      }
    } else {
      return true;
    }
    return false;
  }

  Future<Null> _prepare() async {
    final tasks = await FlutterDownloader.loadTasks();
    int count = 0;
    _tasks = [];

    _tasks!.addAll(_documents.map((document) =>
        _TaskInfo(name: document['name'], link: document['link'])));
    _tasks!.addAll(_images
        .map((image) => _TaskInfo(name: image['name'], link: image['link'])));
    _tasks!.addAll(_videos
        .map((video) => _TaskInfo(name: video['name'], link: video['link'])));

    tasks!.forEach(
      (task) {
        for (_TaskInfo info in _tasks!) {
          if (info.link == task.url) {
            info.taskId = task.taskId;
            info.status = task.status;
            info.progress = task.progress;
          }
        }
      },
    );

    _permissionReady = await _checkPermission();
    if (_permissionReady) {
      await _prepareSaveDir();
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _prepareSaveDir() async {
    _localPath = (await _findLocalPath())!;
    final savedDir = Directory(_localPath);
    bool hasExisted = await savedDir.exists();
    if (!hasExisted) {
      savedDir.create();
    }
  }

  Future<String?> _findLocalPath() async {
    var externalStorageDirPath;
    if (Platform.isAndroid) {
      try {
        externalStorageDirPath = await AndroidPathProvider.downloadsPath;
      } catch (e) {
        final directory = await getExternalStorageDirectory();
        externalStorageDirPath = directory?.path;
      }
    } else if (Platform.isIOS) {
      externalStorageDirPath =
          (await getApplicationDocumentsDirectory()).absolute.path;
    }
    return externalStorageDirPath;
  }

  @override
  void initState() {
    super.initState();
    _bindBackgroundIsolate();
    FlutterDownloader.registerCallback(downloadCallback);
    _isLoading = true;
    _permissionReady = false;
    _prepare();
  }

  @override
  void dispose() {
    _unbindBackgroundIsolate();
    super.dispose();
  }

  void _bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }
    _port.listen((dynamic data) {
      if (debug) {
        print('UI Isolate Callback: $data');
      }

      String? id = data[0];
      DownloadTaskStatus? status = data[1];
      int? progress = data[2];

      if (_tasks != null && _tasks!.isNotEmpty) {
        final task = _tasks!.firstWhere((task) => task.taskId == id);
        setState(() {
          task.status = status;
          task.progress = progress;
        });
      }
    });
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  static void downloadCallback(
      String id, DownloadTaskStatus status, int progress) {
    if (debug) {
      print(
          'Background Isolate Callback: task ($id) is in status ($status) and process ($progress)');
    }
    final SendPort send =
        IsolateNameServer.lookupPortByName('downloader_send_port')!;
    send.send([id, status, progress]);
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(widget.title!),
      ),
      body: ListView.builder(
        itemBuilder: (BuildContext context, int index) {
          return GestureDetector(
            onTap: () {
              _openDownloadedFile(_tasks![index]);
            },
            child: ListTile(
              title: Text(
                _tasks![index].name.toString(),
                style: TextStyle(
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                _tasks![index].taskId.toString(),
                style: TextStyle(
                  fontSize: 15,
                ),
              ),
              trailing: _tasks![index].status == DownloadTaskStatus.undefined
                  ? IconButton(
                      onPressed: () {
                        _requestDownload(_tasks![index]);
                      },
                      icon: Icon(
                        Icons.download_outlined,
                        size: 30,
                        color: Colors.black45,
                      ),
                    )
                  : _tasks![index].status == DownloadTaskStatus.complete
                      ? IconButton(
                          onPressed: () {
                            _delete(_tasks![index]);
                          },
                          icon: Icon(
                            Icons.delete_outline,
                            size: 30,
                            color: Colors.red,
                          ),
                        )
                      : _tasks![index].status == DownloadTaskStatus.running
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '${_tasks![index].progress} %',
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 35,
                                      height: 35,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.red,
                                        value: _tasks![index].progress! / 100,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        _pauseDownload(_tasks![index]);
                                      },
                                      child: Icon(
                                        Icons.pause_outlined,
                                        size: 25,
                                        color: Colors.red,
                                      ),
                                    )
                                  ],
                                ),
                              ],
                            )
                          : _tasks![index].status == DownloadTaskStatus.failed
                              ? IconButton(
                                  onPressed: () {
                                    _retryDownload(_tasks![index]);
                                  },
                                  icon: Icon(
                                    Icons.restart_alt_outlined,
                                    size: 30,
                                    color: Colors.blue,
                                  ),
                                )
                              : _tasks![index].status ==
                                      DownloadTaskStatus.paused
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${_tasks![index].progress} %',
                                        ),
                                        const SizedBox(
                                          width: 10,
                                        ),
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            SizedBox(
                                              width: 35,
                                              height: 35,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.green,
                                                value:
                                                    _tasks![index].progress! /
                                                        100,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                _resumeDownload(_tasks![index]);
                                              },
                                              child: Icon(
                                                Icons.play_arrow,
                                                size: 25,
                                                color: Colors.green,
                                              ),
                                            )
                                          ],
                                        ),
                                      ],
                                    )
                                  : IconButton(
                                      onPressed: () {},
                                      icon: Icon(
                                        Icons.open_in_new,
                                        size: 30,
                                        color: Colors.black,
                                      ),
                                    ),
            ),
          );
        },
        itemCount: _tasks!.length,
      ),
    );
  }

  Future<void> _retryRequestPermission() async {
    final hasGranted = await _checkPermission();
    if (hasGranted) {
      await _prepareSaveDir();
    }
    setState(() {
      _permissionReady = hasGranted;
    });
  }

  void _requestDownload(_TaskInfo task) async {
    task.taskId = await FlutterDownloader.enqueue(
      url: task.link!,
      headers: {"auth": "test_for_sql_encoding"},
      savedDir: _localPath,
      showNotification: true,
      openFileFromNotification: true,
      saveInPublicStorage: true,
    );
  }

  void _cancelDownload(_TaskInfo task) async {
    await FlutterDownloader.cancel(taskId: task.taskId!);
  }

  void _pauseDownload(_TaskInfo task) async {
    await FlutterDownloader.pause(taskId: task.taskId!);
  }

  void _resumeDownload(_TaskInfo task) async {
    String? newTaskId = await FlutterDownloader.resume(taskId: task.taskId!);
    task.taskId = newTaskId;
  }

  void _retryDownload(_TaskInfo task) async {
    String? newTaskId = await FlutterDownloader.retry(taskId: task.taskId!);
    task.taskId = newTaskId;
  }

  Future<bool> _openDownloadedFile(_TaskInfo? task) {
    if (task != null) {
      return FlutterDownloader.open(taskId: task.taskId!);
    } else {
      return Future.value(false);
    }
  }

  void _delete(_TaskInfo task) async {
    await FlutterDownloader.remove(
        taskId: task.taskId!, shouldDeleteContent: true);
    await _prepare();
    setState(() {});
  }
}
