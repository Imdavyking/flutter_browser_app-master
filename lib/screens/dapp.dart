import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import '../screens/main_screen.dart';
import '../screens/saved_urls.dart';
import '../screens/security.dart';
import '../screens/settings.dart';
import '../screens/wallet_main_body.dart';
import '../utils/app_config.dart';
import '../utils/slide_up_panel.dart';
import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:eth_sig_util/util/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:page_transition/page_transition.dart';
import 'package:share/share.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/web3dart.dart' as web3;
import '../utils/rpc_urls.dart';
import 'package:flutter_gen/gen_l10n/app_localization.dart';

class Dapp extends StatefulWidget {
  final String provider;
  final String init;
  final String data;
  const Dapp({
    Key key,
    this.data,
    this.provider,
    this.init,
  }) : super(key: key);
  @override
  State<Dapp> createState() => _DappState();
}

class _DappState extends State<Dapp> {
  @override
  initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pref = Hive.box(secureStorageKey);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pref.get(dappChainIdKey) != null) const Divider(),
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  onTap: () async {
                    Get.back();

                    await Get.to(const Settings());
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          const Icon(Icons.settings),
                          const SizedBox(
                            width: 10,
                          ),
                          Text(
                            AppLocalizations.of(context).info,
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(),
              SizedBox(
                width: double.infinity,
                child: InkWell(
                    onTap: () async {
                      final pref = Hive.box(secureStorageKey);
                      bool hasWallet = pref.get(currentMmenomicKey) != null;

                      bool hasPasscode =
                          pref.get(userUnlockPasscodeKey) != null;
                      Widget dappWidget;
                      Get.back();

                      if (hasWallet) {
                        dappWidget = const WalletMainBody();
                      } else if (hasPasscode) {
                        dappWidget = const MainScreen();
                      } else {
                        dappWidget = const Security();
                      }
                      await Get.to(dappWidget);
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            const Icon(Icons.wallet),
                            const SizedBox(
                              width: 10,
                            ),
                            Text(
                              AppLocalizations.of(context).wallet,
                            )
                          ],
                        ),
                      ),
                    )),
              ),
              const Divider(),
            ],
          ),
        ),
      ),
    );
  }
}
