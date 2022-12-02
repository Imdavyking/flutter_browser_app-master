# Flutter Browser App

![flutter-browser-article-logo](https://user-images.githubusercontent.com/5956938/86740154-b7a48180-c036-11ea-85c1-cbd662f65f84.png)

A Full-Featured Mobile Browser App (such as the Google Chrome mobile browser) created using Flutter and the features offered by the [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) plugin.

It is available on the **Google Play Store** at [https://play.google.com/store/apps/details?id=com.pichillilorenzo.flutter_browser](https://play.google.com/store/apps/details?id=com.pichillilorenzo.flutter_browser)

## Introduction
Article: [Creating a Full-Featured Browser using WebViews in Flutter](https://medium.com/flutter-community/creating-a-full-featured-browser-using-webviews-in-flutter-9c8f2923c574?source=friends_link&sk=55fc8267f351082aa9e73ced546f6bcb).

Check out also the article that introduces the [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) plugin here: [InAppWebView: The Real Power of WebViews in Flutter](https://medium.com/flutter-community/inappwebview-the-real-power-of-webviews-in-flutter-c6d52374209d?source=friends_link&sk=cb74487219bcd85e610a670ee0b447d0).

## Features
- **WebView Tab**, with custom on long-press link/image preview, and how to move from one tab to another without losing the WebView state;
- **Browser App Bar** with the current URL and all popup menu actions such as opening a new tab, a new incognito tab, saving the current URL to the favorite list, saving a page to offline usage, viewing the SSL Certificate used by the website, enable Desktop Mode, etc. (features similar to the Google Chrome App);
- **Developer console**, where you can execute JavaScript code, see some network info, manage the browser storage such as cookies, window.localStorage , etc;
- **Settings page**, where you can update the browser general settings and enable/disable all the features offered by the flutter_inappwebview for each WebView Tab, such as enabling/disabling JavaScript, caching, scrollbars, setting custom user-agent, etc., and all the Android and iOS-specific features;
- **Save** and **restore** the current Browser state.

## Final Result
Video: [Flutter Browser App Final Result](https://drive.google.com/file/d/1wE2yUGwjNBiUy72GOjPIYyDXYQn3ewYn/view?usp=sharing).

If you found this useful and you like the [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) plugin and this App project, give a star to these projects, thanks!














import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_browser/models/browser_model.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'browser.dart';

// ignore: non_constant_identifier_names
 final String WEB_ARCHIVE_DIR;
// ignore: non_constant_identifier_names
 final double TAB_VIEWER_BOTTOM_OFFSET_1;
// ignore: non_constant_identifier_names
 final double TAB_VIEWER_BOTTOM_OFFSET_2;
// ignore: non_constant_identifier_names
 final double TAB_VIEWER_BOTTOM_OFFSET_3;
// ignore: constant_identifier_names
const double TAB_VIEWER_TOP_OFFSET_1 = 0.0;
// ignore: constant_identifier_names
const double TAB_VIEWER_TOP_OFFSET_2 = 10.0;
// ignore: constant_identifier_names
const double TAB_VIEWER_TOP_OFFSET_3 = 20.0;
// ignore: constant_identifier_names
const double TAB_VIEWER_TOP_SCALE_TOP_OFFSET = 250.0;
// ignore: constant_identifier_names
const double TAB_VIEWER_TOP_SCALE_BOTTOM_OFFSET = 230.0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  WEB_ARCHIVE_DIR = (await getApplicationSupportDirectory()).path;

  TAB_VIEWER_BOTTOM_OFFSET_1 = 130.0;
  TAB_VIEWER_BOTTOM_OFFSET_2 = 140.0;
  TAB_VIEWER_BOTTOM_OFFSET_3 = 150.0;

  await FlutterDownloader.initialize(
    debug: kDebugMode
  );

  await Permission.camera.request();
  await Permission.microphone.request();
  await Permission.storage.request();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => WebViewModel(),
        ),
        ChangeNotifierProxyProvider<WebViewModel, BrowserModel>(
          update: (context, webViewModel, browserModel) {
            browserModel.setCurrentWebViewModel(webViewModel);
            return browserModel;
          },
          create: (BuildContext context) => BrowserModel(),
        ),
      ],
      child: const FlutterBrowserApp(),
    ),
  );
}

class FlutterBrowserApp extends StatelessWidget {
  const FlutterBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Browser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const Browser(),
      },
    );
  }
}
