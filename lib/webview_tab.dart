import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_browser/main.dart';
import 'package:flutter_browser/models/webview_model.dart';
import 'package:flutter_browser/util.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import 'javascript_console_result.dart';
import 'long_press_alert_dialog.dart';
import 'models/browser_model.dart';
import 'utils/app_config.dart';
import 'utils/rpc_urls.dart';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:web3dart/web3dart.dart' as web3;

final webViewTabStateKey = GlobalKey<_WebViewTabState>();

class WebViewTab extends StatefulWidget {
  final String provider;
  final String init;
  const WebViewTab(
    this.provider,
    this.init, {
    Key key,
    this.webViewModel,
  }) : super(key: key);

  final WebViewModel webViewModel;

  @override
  State<WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<WebViewTab> with WidgetsBindingObserver {
  InAppWebViewController _webViewController;
  PullToRefreshController _pullToRefreshController;
  FindInteractionController _findInteractionController;
  bool _isWindowClosed = false;
  String initJs = '';
  final TextEditingController _httpAuthUsernameController =
      TextEditingController();
  final TextEditingController _httpAuthPasswordController =
      TextEditingController();

  @override
  void initState() {
    initJs = widget.init;
    WidgetsBinding.instance.addObserver(this);
    super.initState();

    _pullToRefreshController = kIsWeb
        ? null
        : PullToRefreshController(
            settings: PullToRefreshSettings(color: Colors.blue),
            onRefresh: () async {
              if (defaultTargetPlatform == TargetPlatform.android) {
                _webViewController.reload();
              } else if (defaultTargetPlatform == TargetPlatform.iOS) {
                _webViewController.loadUrl(
                    urlRequest:
                        URLRequest(url: await _webViewController.getUrl()));
              }
            },
          );

    _findInteractionController = FindInteractionController();
  }

  @override
  void dispose() {
    _webViewController = null;
    widget.webViewModel.webViewController = null;
    widget.webViewModel.pullToRefreshController = null;
    widget.webViewModel.findInteractionController = null;

    _httpAuthUsernameController.dispose();
    _httpAuthPasswordController.dispose();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  changeBrowserChainId_(int chainId, String rpc) async {
    if (_webViewController == null) return;
    initJs = await changeBlockChainAndReturnInit(
      getEthereumDetailsFromChainId(chainId)['coinType'],
      chainId,
      rpc,
    );

    await _webViewController.removeAllUserScripts();
    await _webViewController.addUserScript(
      userScript: UserScript(
        source: widget.provider + initJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
    await _webViewController.reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_webViewController != null && Util.isAndroid()) {
      if (state == AppLifecycleState.paused) {
        pauseAll();
      } else {
        resumeAll();
      }
    }
  }

  void pauseAll() {
    if (Util.isAndroid()) {
      _webViewController.pause();
    }
    pauseTimers();
  }

  void resumeAll() {
    if (Util.isAndroid()) {
      _webViewController.resume();
    }
    resumeTimers();
  }

  void pause() {
    if (Util.isAndroid()) {
      _webViewController.pause();
    }
  }

  void resume() {
    if (Util.isAndroid()) {
      _webViewController.resume();
    }
  }

  void pauseTimers() {
    _webViewController.pauseTimers();
  }

  void resumeTimers() {
    _webViewController.resumeTimers();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: _buildWebView(),
    );
  }

  InAppWebView _buildWebView() {
    var browserModel = Provider.of<BrowserModel>(context, listen: true);
    var settings = browserModel.getSettings();
    var currentWebViewModel = Provider.of<WebViewModel>(context, listen: true);

    if (Util.isAndroid()) {
      InAppWebViewController.setWebContentsDebuggingEnabled(
          settings.debuggingEnabled);
    }

    var initialSettings = widget.webViewModel.settings;
    initialSettings.useOnDownloadStart = true;
    initialSettings.useOnLoadResource = true;
    initialSettings.useShouldOverrideUrlLoading = true;
    initialSettings.javaScriptCanOpenWindowsAutomatically = true;
    initialSettings.userAgent =
        "Mozilla/5.0 (Linux; Android 9; LG-H870 Build/PKQ1.190522.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/83.0.4103.106 Mobile Safari/537.36";
    initialSettings.transparentBackground = true;

    initialSettings.safeBrowsingEnabled = true;
    initialSettings.disableDefaultErrorPage = true;
    initialSettings.supportMultipleWindows = true;
    initialSettings.verticalScrollbarThumbColor =
        const Color.fromRGBO(0, 0, 0, 0.5);
    initialSettings.horizontalScrollbarThumbColor =
        const Color.fromRGBO(0, 0, 0, 0.5);

    initialSettings.allowsLinkPreview = false;
    initialSettings.isFraudulentWebsiteWarningEnabled = true;
    initialSettings.disableLongPressContextMenuOnLinks = true;
    initialSettings.allowingReadAccessTo = WebUri('file://$WEB_ARCHIVE_DIR/');

    return InAppWebView(
      initialUrlRequest: URLRequest(url: widget.webViewModel.url),
      initialSettings: initialSettings,
      windowId: widget.webViewModel.windowId,
      pullToRefreshController: _pullToRefreshController,
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: widget.provider + initJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        )
      ]),
      findInteractionController: _findInteractionController,
      onWebViewCreated: (controller) async {
        initialSettings.transparentBackground = false;
        await controller.setSettings(settings: initialSettings);

        _webViewController = controller;
        _webViewController.addJavaScriptHandler(
          handlerName: 'requestAccounts',
          callback: (args) async {
            final pref = Hive.box(secureStorageKey);
            final mnemonic = pref.get(currentMmenomicKey);

            int chainId = pref.get(dappChainIdKey);
            final blockChainDetails = getEthereumDetailsFromChainId(chainId);
            final web3Response = await getEthereumFromMemnomic(
              mnemonic,
              blockChainDetails['coinType'],
            );

            final sendingAddress = web3Response['eth_wallet_address'];
            final id = args[0];
            try {
              await _webViewController.evaluateJavascript(
                source:
                    'AlphaWallet.executeCallback($id, null, ["$sendingAddress"]);',
              );
            } catch (e) {
              //  replace all quotes in error
              final error = e.toString().replaceAll('"', '\'');

              await _webViewController.evaluateJavascript(
                source: 'AlphaWallet.executeCallback($id, "$error",null);',
              );
            }
          },
        );
        _webViewController.addJavaScriptHandler(
          handlerName: 'walletAddEthereumChain',
          callback: (args) async {
            final pref = Hive.box(secureStorageKey);
            int chainId = pref.get(dappChainIdKey);
            final id = args[0];

            final switchChainId =
                BigInt.parse(json.decode(args[1])['chainId']).toInt();

            final currentChainIdData = getEthereumDetailsFromChainId(chainId);

            final switchChainIdData =
                getEthereumDetailsFromChainId(switchChainId);

            if (chainId == switchChainId) {
              await _webViewController.evaluateJavascript(
                  source:
                      'AlphaWallet.executeCallback($id, "cancelled", null);');
              return;
            }

            if (switchChainIdData == null) {
              await _webViewController.evaluateJavascript(
                  source:
                      'AlphaWallet.executeCallback($id, "we can not add this block", null);');
            } else {
              switchEthereumChain(
                context: context,
                currentChainIdData: currentChainIdData,
                switchChainIdData: switchChainIdData,
                onConfirm: () async {
                  await changeBrowserChainId_(
                    switchChainIdData['chainId'],
                    switchChainIdData['rpc'],
                  );

                  await _webViewController.evaluateJavascript(
                    source: 'AlphaWallet.executeCallback($id, null, null);',
                  );
                  Navigator.pop(context);
                },
                onReject: () async {
                  await _webViewController.evaluateJavascript(
                      source:
                          'AlphaWallet.executeCallback($id, "user rejected switch", null);');
                  Navigator.pop(context);
                },
              );
            }
          },
        );
        _webViewController.addJavaScriptHandler(
          handlerName: 'walletSwitchEthereumChain',
          callback: (args) async {
            final pref = Hive.box(secureStorageKey);
            int chainId = pref.get(dappChainIdKey);
            final id = args[0];

            final switchChainId =
                BigInt.parse(json.decode(args[1])['chainId']).toInt();

            final currentChainIdData = getEthereumDetailsFromChainId(chainId);

            final switchChainIdData =
                getEthereumDetailsFromChainId(switchChainId);

            if (chainId == switchChainId) {
              await _webViewController.evaluateJavascript(
                source: 'AlphaWallet.executeCallback($id, "cancelled", null);',
              );
              return;
            }

            if (switchChainIdData == null) {
              await _webViewController.evaluateJavascript(
                source:
                    'AlphaWallet.executeCallback($id, "we can not add this block", null);',
              );
            } else {
              switchEthereumChain(
                context: context,
                currentChainIdData: currentChainIdData,
                switchChainIdData: switchChainIdData,
                onConfirm: () async {
                  await changeBrowserChainId_(
                    switchChainIdData['chainId'],
                    switchChainIdData['rpc'],
                  );

                  await _webViewController.evaluateJavascript(
                    source: 'AlphaWallet.executeCallback($id, null, null);',
                  );
                  Get.back();
                },
                onReject: () async {
                  await _webViewController.evaluateJavascript(
                    source:
                        'AlphaWallet.executeCallback($id, "user rejected switch", null);',
                  );
                  Get.back();
                },
              );
            }
          },
        );
        _webViewController.addJavaScriptHandler(
          handlerName: 'ethCall',
          callback: (args) async {
            final pref = Hive.box(secureStorageKey);
            int chainId = pref.get(dappChainIdKey);
            final rpc = getEthereumDetailsFromChainId(chainId)['rpc'];
            final id = args[0];
            final tx = json.decode(args[1]) as Map;
            try {
              final client = web3.Web3Client(
                rpc,
                Client(),
              );

              final mnemonic = pref.get(currentMmenomicKey);
              final blockChainDetails = getEthereumDetailsFromChainId(chainId);
              final web3Response = await getEthereumFromMemnomic(
                mnemonic,
                blockChainDetails['coinType'],
              );

              final sendingAddress = web3Response['eth_wallet_address'];

              final response = await client.callRaw(
                sender: EthereumAddress.fromHex(sendingAddress),
                contract: EthereumAddress.fromHex(tx['to']),
                data: txDataToUintList(tx['data']),
              );
              await _webViewController.evaluateJavascript(
                source: 'AlphaWallet.executeCallback($id, null, "$response");',
              );
            } catch (e) {
              final error = e.toString().replaceAll('"', '\'');

              await _webViewController.evaluateJavascript(
                source: 'AlphaWallet.executeCallback($id, "$error",null);',
              );
            }
          },
        );
        _webViewController.addJavaScriptHandler(
          handlerName: 'signTransaction',
          callback: (args) async {
            final pref = Hive.box(secureStorageKey);
            int chainId = pref.get(dappChainIdKey);
            final mnemonic = pref.get(currentMmenomicKey);

            final blockChainDetails = getEthereumDetailsFromChainId(chainId);
            final rpc = blockChainDetails['rpc'];
            final web3Response = await getEthereumFromMemnomic(
              mnemonic,
              blockChainDetails['coinType'],
            );

            final privateKey = web3Response['eth_wallet_privateKey'];

            final sendingAddress = web3Response['eth_wallet_address'];
            final client = web3.Web3Client(
              rpc,
              Client(),
            );
            final credentials = EthPrivateKey.fromHex(privateKey);

            final id = args[0];
            final to = args[1];
            final value = args[2];
            final nonce = args[3] == -1 ? null : args[3];
            final gasPrice = args[5];
            final data = args[6];

            await signTransaction(
              gasPriceInWei_: gasPrice,
              to: to,
              from: sendingAddress,
              txData: data,
              valueInWei_: value,
              gasInWei_: null,
              networkIcon: null,
              context: context,
              blockChainCurrencySymbol: blockChainDetails['symbol'],
              name: '',
              onConfirm: () async {
                try {
                  final signedTransaction = await client.signTransaction(
                    credentials,
                    Transaction(
                      to: to != null ? EthereumAddress.fromHex(to) : null,
                      value: value != null
                          ? EtherAmount.inWei(
                              BigInt.parse(value),
                            )
                          : null,
                      nonce: nonce,
                      gasPrice: gasPrice != null
                          ? EtherAmount.inWei(BigInt.parse(gasPrice))
                          : null,
                      data: txDataToUintList(data),
                    ),
                    chainId: chainId,
                  );

                  final response =
                      await client.sendRawTransaction(signedTransaction);

                  await _webViewController.evaluateJavascript(
                    source:
                        'AlphaWallet.executeCallback($id, null, "$response");',
                  );
                } catch (e) {
                  final error = e.toString().replaceAll('"', '\'');

                  await _webViewController.evaluateJavascript(
                    source: 'AlphaWallet.executeCallback($id, "$error",null);',
                  );
                } finally {
                  Get.back();
                }
              },
              onReject: () async {
                await _webViewController.evaluateJavascript(
                  source:
                      'AlphaWallet.executeCallback($id, "user rejected transaction",null);',
                );
                Get.back();
              },
              title: 'Sign Transaction',
              chainId: chainId,
            );
          },
        );

        _webViewController.addJavaScriptHandler(
          handlerName: 'signMessage',
          callback: (args) async {
            final pref = Hive.box(secureStorageKey);
            int chainId = pref.get(dappChainIdKey);
            final mnemonic = pref.get(currentMmenomicKey);

            final blockChainDetails = getEthereumDetailsFromChainId(chainId);
            final web3Response = await getEthereumFromMemnomic(
              mnemonic,
              blockChainDetails['coinType'],
            );

            final privateKey = web3Response['eth_wallet_privateKey'];

            final credentials = EthPrivateKey.fromHex(privateKey);

            final id = args[0];
            String data = args[1];
            String messageType = args[2];
            if (messageType == typedMessageSignKey) {
              data = json.decode(data)['data'];
            }

            await signMessage(
              context: context,
              messageType: messageType,
              data: data,
              networkIcon: null,
              name: null,
              onConfirm: () async {
                try {
                  String signedDataHex;
                  Uint8List signedData;
                  if (messageType == typedMessageSignKey) {
                    signedDataHex = EthSigUtil.signTypedData(
                      privateKey: privateKey,
                      jsonData: data,
                      version: TypedDataVersion.V4,
                    );
                  } else if (messageType == personalSignKey) {
                    signedData = await credentials.signPersonalMessage(
                      txDataToUintList(data),
                    );
                    signedDataHex = bytesToHex(signedData, include0x: true);
                  } else if (messageType == normalSignKey) {
                    try {
                      signedDataHex = EthSigUtil.signMessage(
                        privateKey: privateKey,
                        message: txDataToUintList(data),
                      );
                    } catch (e) {
                      signedData = await credentials.signPersonalMessage(
                        txDataToUintList(data),
                      );
                      signedDataHex = bytesToHex(signedData, include0x: true);
                    }
                  }
                  await _webViewController.evaluateJavascript(
                    source:
                        'AlphaWallet.executeCallback($id, null, "$signedDataHex");',
                  );
                } catch (e) {
                  final error = e.toString().replaceAll('"', '\'');

                  await _webViewController.evaluateJavascript(
                    source: 'AlphaWallet.executeCallback($id, "$error",null);',
                  );
                } finally {
                  Get.back();
                }
              },
              onReject: () {
                _webViewController.evaluateJavascript(
                  source:
                      'AlphaWallet.executeCallback($id, "user rejected signature",null);',
                );
                Get.back();
              },
            );
          },
        );

        widget.webViewModel.webViewController = controller;
        widget.webViewModel.pullToRefreshController = _pullToRefreshController;
        widget.webViewModel.findInteractionController =
            _findInteractionController;

        if (Util.isAndroid()) {
          controller.startSafeBrowsing();
        }

        widget.webViewModel.settings = await controller.getSettings();

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      onLoadStart: (controller, url) async {
        widget.webViewModel.isSecure = Util.urlIsSecure(url);
        widget.webViewModel.url = url;
        widget.webViewModel.loaded = false;
        widget.webViewModel.setLoadedResources([]);
        widget.webViewModel.setJavaScriptConsoleResults([]);

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        } else if (widget.webViewModel.needsToCompleteInitialLoad) {
          controller.stopLoading();
        }
      },
      onLoadStop: (controller, url) async {
        _pullToRefreshController.endRefreshing();

        widget.webViewModel.url = url;
        widget.webViewModel.favicon = null;
        widget.webViewModel.loaded = true;

        var sslCertificateFuture = _webViewController.getCertificate();
        var titleFuture = _webViewController.getTitle();
        var faviconsFuture = _webViewController.getFavicons();

        var sslCertificate = await sslCertificateFuture;
        if (sslCertificate == null && !Util.isLocalizedContent(url)) {
          widget.webViewModel.isSecure = false;
        }

        widget.webViewModel.title = await titleFuture;

        List<Favicon> favicons = await faviconsFuture;
        if (favicons != null && favicons.isNotEmpty) {
          for (var fav in favicons) {
            if (widget.webViewModel.favicon == null) {
              widget.webViewModel.favicon = fav;
            } else {
              if ((widget.webViewModel.favicon.width == null &&
                      !widget.webViewModel.favicon.url
                          .toString()
                          .endsWith("favicon.ico")) ||
                  (fav.width != null &&
                      widget.webViewModel.favicon.width != null &&
                      fav.width > widget.webViewModel.favicon.width)) {
                widget.webViewModel.favicon = fav;
              }
            }
          }
        }

        if (isCurrentTab(currentWebViewModel)) {
          widget.webViewModel.needsToCompleteInitialLoad = false;
          currentWebViewModel.updateWithValue(widget.webViewModel);

          var screenshotData = _webViewController
              ?.takeScreenshot(
                  screenshotConfiguration: ScreenshotConfiguration(
                      compressFormat: CompressFormat.JPEG, quality: 20))
              .timeout(
                const Duration(milliseconds: 1500),
                onTimeout: () => null,
              );
          widget.webViewModel.screenshot = await screenshotData;
        }
      },
      onProgressChanged: (controller, progress) {
        if (progress == 100) {
          _pullToRefreshController.endRefreshing();
        }

        widget.webViewModel.progress = progress / 100;

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      onUpdateVisitedHistory: (controller, url, androidIsReload) async {
        widget.webViewModel.url = url;
        widget.webViewModel.title = await _webViewController.getTitle();

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      onLongPressHitTestResult: (controller, hitTestResult) async {
        if (LongPressAlertDialog.hitTestResultSupported
            .contains(hitTestResult.type)) {
          var requestFocusNodeHrefResult =
              await _webViewController.requestFocusNodeHref();

          if (requestFocusNodeHrefResult != null) {
            showDialog(
              context: context,
              builder: (context) {
                return LongPressAlertDialog(
                  webViewModel: widget.webViewModel,
                  hitTestResult: hitTestResult,
                  requestFocusNodeHrefResult: requestFocusNodeHrefResult,
                );
              },
            );
          }
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        Color consoleTextColor = Colors.black;
        Color consoleBackgroundColor = Colors.transparent;
        IconData consoleIconData;
        Color consoleIconColor;
        if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
          consoleTextColor = Colors.red;
          consoleIconData = Icons.report_problem;
          consoleIconColor = Colors.red;
        } else if (consoleMessage.messageLevel == ConsoleMessageLevel.TIP) {
          consoleTextColor = Colors.blue;
          consoleIconData = Icons.info;
          consoleIconColor = Colors.blueAccent;
        } else if (consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
          consoleBackgroundColor = const Color.fromRGBO(255, 251, 227, 1);
          consoleIconData = Icons.report_problem;
          consoleIconColor = Colors.orangeAccent;
        }

        widget.webViewModel.addJavaScriptConsoleResults(JavaScriptConsoleResult(
          data: consoleMessage.message,
          textColor: consoleTextColor,
          backgroundColor: consoleBackgroundColor,
          iconData: consoleIconData,
          iconColor: consoleIconColor,
        ));

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      onLoadResource: (controller, resource) {
        widget.webViewModel.addLoadedResources(resource);

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        var url = navigationAction.request.url;

        if (url != null &&
            !["http", "https", "file", "chrome", "data", "javascript", "about"]
                .contains(url.scheme)) {
          if (await canLaunchUrl(url)) {
            // Launch the App
            await launchUrl(
              url,
            );
            // and cancel the request
            return NavigationActionPolicy.CANCEL;
          }
        }

        return NavigationActionPolicy.ALLOW;
      },
      onDownloadStartRequest: (controller, url) async {
        String path = url.url.path;
        String fileName = path.substring(path.lastIndexOf('/') + 1);

        await FlutterDownloader.enqueue(
          url: url.toString(),
          fileName: fileName,
          savedDir: (await getTemporaryDirectory()).path,
          showNotification: true,
          openFileFromNotification: true,
        );
      },
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        var sslError = challenge.protectionSpace.sslError;
        if (sslError != null && (sslError.code != null)) {
          if (Util.isIOS() && sslError.code == SslErrorType.UNSPECIFIED) {
            return ServerTrustAuthResponse(
                action: ServerTrustAuthResponseAction.PROCEED);
          }
          widget.webViewModel.isSecure = false;
          if (isCurrentTab(currentWebViewModel)) {
            currentWebViewModel.updateWithValue(widget.webViewModel);
          }
          return ServerTrustAuthResponse(
              action: ServerTrustAuthResponseAction.CANCEL);
        }
        return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED);
      },
      onReceivedError: (controller, request, error) async {
        var isForMainFrame = request.isForMainFrame ?? false;
        if (!isForMainFrame) {
          return;
        }

        _pullToRefreshController.endRefreshing();

        if (Util.isIOS() && error.type == WebResourceErrorType.CANCELLED) {
          // NSURLErrorDomain
          return;
        }

        var errorUrl = request.url;

        _webViewController.loadData(data: """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
    <style>
    ${await InAppWebViewController.tRexRunnerCss}
    </style>
    <style>
    .interstitial-wrapper {
        box-sizing: border-box;
        font-size: 1em;
        line-height: 1.6em;
        margin: 0 auto 0;
        max-width: 600px;
        width: 100%;
    }
    </style>
</head>
<body>
    ${await InAppWebViewController.tRexRunnerHtml}
    <div class="interstitial-wrapper">
      <h1>Website not available</h1>
      <p>Could not load web pages at <strong>$errorUrl</strong> because:</p>
      <p>${error.description}</p>
    </div>
</body>
    """, baseUrl: errorUrl, historyUrl: errorUrl);

        widget.webViewModel.url = errorUrl;
        widget.webViewModel.isSecure = false;

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      onTitleChanged: (controller, title) async {
        widget.webViewModel.title = title;

        if (isCurrentTab(currentWebViewModel)) {
          currentWebViewModel.updateWithValue(widget.webViewModel);
        }
      },
      onCreateWindow: (controller, createWindowRequest) async {
        var webViewTab = WebViewTab(
          '',
          '',
          key: GlobalKey(),
          webViewModel: WebViewModel(
              url: WebUri("about:blank"),
              windowId: createWindowRequest.windowId),
        );

        browserModel.addTab(webViewTab);

        return true;
      },
      onCloseWindow: (controller) {
        if (_isWindowClosed) {
          return;
        }
        _isWindowClosed = true;
        if (widget.webViewModel.tabIndex != null) {
          browserModel.closeTab(widget.webViewModel.tabIndex);
        }
      },
      onPermissionRequest: (controller, permissionRequest) async {
        return PermissionResponse(
            resources: permissionRequest.resources,
            action: PermissionResponseAction.GRANT);
      },
      onReceivedHttpAuthRequest: (controller, challenge) async {
        var action = await createHttpAuthDialog(challenge);
        return HttpAuthResponse(
            username: _httpAuthUsernameController.text.trim(),
            password: _httpAuthPasswordController.text,
            action: action,
            permanentPersistence: true);
      },
    );
  }

  bool isCurrentTab(WebViewModel currentWebViewModel) {
    return currentWebViewModel.tabIndex == widget.webViewModel.tabIndex;
  }

  Future<HttpAuthResponseAction> createHttpAuthDialog(
      URLAuthenticationChallenge challenge) async {
    HttpAuthResponseAction action = HttpAuthResponseAction.CANCEL;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Login"),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(challenge.protectionSpace.host),
              TextField(
                decoration: const InputDecoration(labelText: "Username"),
                controller: _httpAuthUsernameController,
              ),
              TextField(
                decoration: const InputDecoration(labelText: "Password"),
                controller: _httpAuthPasswordController,
                obscureText: true,
              ),
            ],
          ),
          actions: <Widget>[
            ElevatedButton(
              child: const Text("Cancel"),
              onPressed: () {
                action = HttpAuthResponseAction.CANCEL;
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text("Ok"),
              onPressed: () {
                action = HttpAuthResponseAction.PROCEED;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    return action;
  }

  void onShowTab() async {
    resume();
    if (widget.webViewModel.needsToCompleteInitialLoad) {
      widget.webViewModel.needsToCompleteInitialLoad = false;
      await widget.webViewModel.webViewController
          ?.loadUrl(urlRequest: URLRequest(url: widget.webViewModel.url));
    }
  }

  void onHideTab() async {
    pause();
  }
}
