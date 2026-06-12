import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  // Ensures all Flutter components are completely bound and ready before modifying platform UI settings
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    await GoogleSignInDart.register(
      clientId:
          '594735884693-v0saapde88haedikdabrhdea0sjejcg9.apps.googleusercontent.com',
    );
  }

  // Immersive Sticky mode hides both the top status bar and bottom navigation bar completely
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (e) {
    debugPrint("SystemUI error: $e");
  }

  // Initialize Firebase
  try {
    if (Platform.isWindows) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyD6UmuXUJPjSXWh4bdeHxSG3GNrTT0or0o',
          appId: '1:594735884693:android:512892312fe4e206a1ae9c',
          messagingSenderId: '594735884693',
          projectId: 'billing-app-61a0e',
          storageBucket: 'billing-app-61a0e.firebasestorage.app',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint("Firebase initialization skipped or failed: $e");
  }

  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1300, 850),
        minimumSize: Size(1300, 850),
        maximumSize: Size(1300, 850),
        center: true,
        title: "BILLING APP",
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setResizable(false);
        await windowManager.setMaximizable(false);
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint("WindowManager error: $e");
    }
  }

  runApp(SmartBillingApp(key: smartBillingAppKey));
}

// Global key to allow rebuilding the root app widget when theme changes
final GlobalKey<_SmartBillingAppState> smartBillingAppKey =
    GlobalKey<_SmartBillingAppState>();

class SmartBillingApp extends StatefulWidget {
  SmartBillingApp({super.key});
  @override
  State<SmartBillingApp> createState() => _SmartBillingAppState();
}

class _SmartBillingAppState extends State<SmartBillingApp> {
  void rebuildApp() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: currentThemeSetting == "LIGHT"
              ? Brightness.light
              : Brightness.dark,
        ),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: currentThemeSetting == "LIGHT"
              ? Colors.grey.shade100
              : Colors.black26,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Colors.deepPurpleAccent,
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
          elevation: 8,
        ),
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          elevation: 2,
          margin: EdgeInsets.all(8),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// --- GLOBAL DATA ---
Map<String, List<Map<String, String>>> globalInventory = {};
List<Map<String, dynamic>> globalParties = [];
Map<String, String> globalCategoryColors = {};
String currentLayoutSetting = "HL";
String globalShopName = "RETAIL INVOICE";
String currentThemeSetting = "LIGHT";
User? currentFirebaseUser;

// --- COLOR CONSTANTS & PICKER UI ---
const List<String> presetColors = [
  "#E0E0E0",
  "#FFF59D",
  "#C8E6C9",
  "#B2EBF2",
  "#BBDEFB",
  "#F8BBD0",
  "#9E9E9E",
  "#D7CCC8",
  "#AED581",
  "#4DB6AC",
  "#64B5F6",
  "#CE93D8",
  "#FFCA28",
  "#FF9800",
  "#4CAF50",
  "#2196F3",
  "#BA68C8",
  "#F06292",
  "#F4511E",
  "#F44336",
  "#827717",
  "#3F51B5",
  "#9C27B0",
  "#E91E63",
  "#616161",
  "#795548",
  "#B71C1C",
  "#1B5E20",
  "#0D47A1",
  "#4A148C",
];

Color parseHexColor(String? hexString) {
  if (hexString == null || hexString.isEmpty) return Colors.transparent;
  try {
    return Color(int.parse(hexString.replaceFirst('#', '0xFF')));
  } catch (e) {
    return Colors.transparent;
  }
}

Future<String?> showColorPickerDialog(
  BuildContext context,
  String? currentColor, {
  bool isEditing = false,
  TextEditingController? categoryNameController,
}) async {
  String selected = currentColor ?? presetColors.first;
  return await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: Text(
              "CHOOSE COLOUR",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.blueGrey,
              ),
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (categoryNameController != null) ...[
                    TextField(
                      controller: categoryNameController,
                      decoration: InputDecoration(
                        labelText: "Category Name",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: presetColors.length,
                      itemBuilder: (context, index) {
                        final colorHex = presetColors[index];
                        final isSelected = colorHex == selected;
                        int colorInt = int.parse(
                          colorHex.replaceFirst('#', '0xFF'),
                        );

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selected = colorHex;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Color(colorInt),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black,
                                      width: 3,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: Text(isEditing ? "SAVE" : "ADD"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx, null),
                      child: const Text("CLOSE"),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

// --- LOCAL STORAGE HELPER LOGIC ---
class LocalDatabase {
  static String _getWindowsSettingsDir() {
    return "${File(Platform.resolvedExecutable).parent.path}\\Billing APP\\INTERNAL_SETTINGS";
  }

  static String _getWindowsBackupsDir() {
    return "${File(Platform.resolvedExecutable).parent.path}\\Billing APP\\INVENTORY BACKUPS";
  }

  static String _getWindowsBillsDir() {
    return "${File(Platform.resolvedExecutable).parent.path}\\Billing APP\\MYBILLS";
  }

  static Future<Uri?> getBaseFolderUri() async {
    if (Platform.isWindows) return null;
    final prefs = await SharedPreferences.getInstance();
    String? uriString = prefs.getString('settings_folder_uri');
    if (uriString == null) return null;

    final rootUri = Uri.parse(uriString);
    var billingAppFolder = await saf.child(rootUri, "Billing APP");
    if (billingAppFolder == null) {
      var doc = await saf.createDirectory(rootUri, "Billing APP");
      return doc?.uri;
    }
    return billingAppFolder.uri;
  }

  static Future<Uri?> getSettingsFolderUri() async {
    if (Platform.isWindows) return null;
    final baseUri = await getBaseFolderUri();
    if (baseUri == null) return null;
    var folder = await saf.child(baseUri, "INTERNAL_SETTINGS");
    if (folder == null) {
      var doc = await saf.createDirectory(baseUri, "INTERNAL_SETTINGS");
      return doc?.uri;
    }
    return folder.uri;
  }

  static Future<void> savePartiesToDisk() async {
    try {
      final content = jsonEncode(globalParties);
      if (Platform.isWindows) {
        String dir = _getWindowsSettingsDir();
        if (!Directory(dir).existsSync()) {
          Directory(dir).createSync(recursive: true);
        }
        await File("$dir\\party_details.json").writeAsString(content);
      } else {
        final settingsUri = await getSettingsFolderUri();
        if (settingsUri == null) return;
        var file = await saf.child(settingsUri, 'party_details.json');
        if (file == null) {
          await saf.createFileAsString(
            settingsUri,
            mimeType: "application/json",
            displayName: "party_details.json",
            content: content,
          );
        } else {
          await saf.writeToFileAsString(
            file.uri,
            content: content,
            mode: FileMode.write,
          );
        }
      }
    } catch (e) {
      debugPrint("Error saving parties: $e");
    }
  }

  static Future<void> loadPartiesFromDisk() async {
    try {
      String? content;
      if (Platform.isWindows) {
        String fileStr = "${_getWindowsSettingsDir()}\\party_details.json";
        if (File(fileStr).existsSync()) {
          content = await File(fileStr).readAsString();
        }
      } else {
        final settingsUri = await getSettingsFolderUri();
        if (settingsUri == null) return;
        var file = await saf.child(settingsUri, 'party_details.json');
        if (file != null) {
          final bytes = await saf.getDocumentContent(file.uri);
          if (bytes != null) content = utf8.decode(bytes);
        }
      }

      if (content != null) {
        List<dynamic> decoded = jsonDecode(content);
        globalParties = decoded
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      debugPrint("Error loading parties: $e");
    }
  }

  static Future<void> saveToDisk() async {
    try {
      final content = jsonEncode({
        "_version": 2,
        "inventory": globalInventory,
        "categoryColors": globalCategoryColors,
      });
      final bytes = Uint8List.fromList(utf8.encode(content));

      if (Platform.isWindows) {
        String dir = _getWindowsSettingsDir();
        Directory(dir).createSync(recursive: true);
        await File("$dir\\inventory_db.json").writeAsBytes(bytes);
        return;
      }

      final settingsUri = await getSettingsFolderUri();
      if (settingsUri == null) return;
      var file = await saf.child(settingsUri, 'inventory_db.json');
      if (file == null) {
        await saf.createFileAsBytes(
          settingsUri,
          mimeType: 'application/json',
          displayName: 'inventory_db.json',
          bytes: bytes,
        );
      } else {
        await saf.writeToFileAsBytes(file.uri, bytes: bytes);
      }
    } catch (e) {
      debugPrint("Error auto-saving database: $e");
    }
  }

  static Future<void> loadFromDisk() async {
    try {
      String? content;
      if (Platform.isWindows) {
        String fileStr = "${_getWindowsSettingsDir()}\\inventory_db.json";
        if (File(fileStr).existsSync()) {
          content = await File(fileStr).readAsString();
        }
      } else {
        final settingsUri = await getSettingsFolderUri();
        if (settingsUri == null) return;
        var file = await saf.child(settingsUri, 'inventory_db.json');
        if (file != null) {
          final bytes = await saf.getDocumentContent(file.uri);
          if (bytes != null) content = utf8.decode(bytes);
        }
      }

      if (content != null) {
        Map<String, dynamic> decoded = jsonDecode(content);

        if (decoded.containsKey('_version') && decoded['_version'] == 2) {
          Map<String, dynamic> inv = decoded['inventory'] ?? {};
          Map<String, List<Map<String, String>>> loadedInventory = {};
          inv.forEach((key, value) {
            loadedInventory[key] = (value as List)
                .map((item) => Map<String, String>.from(item))
                .toList();
          });
          globalInventory = loadedInventory;

          Map<String, dynamic> colors = decoded['categoryColors'] ?? {};
          globalCategoryColors = colors.map(
            (key, value) => MapEntry(key, value.toString()),
          );
        } else {
          // Legacy Format Migration
          Map<String, List<Map<String, String>>> loadedInventory = {};
          decoded.forEach((key, value) {
            loadedInventory[key] = (value as List)
                .map((item) => Map<String, String>.from(item))
                .toList();
          });
          globalInventory = loadedInventory;
          globalCategoryColors = {}; // Default empty for older formats
        }
      }
    } catch (e) {
      debugPrint("Error auto-loading database: $e");
    }
  }

  static Future<void> saveAppSettings() async {
    try {
      final content = jsonEncode({
        "layout": currentLayoutSetting,
        "shopName": globalShopName,
        "theme": currentThemeSetting,
      });
      final bytes = Uint8List.fromList(utf8.encode(content));

      if (Platform.isWindows) {
        String dir = _getWindowsSettingsDir();
        Directory(dir).createSync(recursive: true);
        await File("$dir\\app_settings.json").writeAsBytes(bytes);
        return;
      }

      final settingsUri = await getSettingsFolderUri();
      if (settingsUri == null) return;
      var file = await saf.child(settingsUri, 'app_settings.json');
      if (file == null) {
        await saf.createFileAsBytes(
          settingsUri,
          mimeType: 'application/json',
          displayName: 'app_settings.json',
          bytes: bytes,
        );
      } else {
        await saf.writeToFileAsBytes(file.uri, bytes: bytes);
      }
    } catch (e) {
      debugPrint("Error saving app configuration: $e");
    }
  }

  static Future<void> loadAppSettings() async {
    try {
      String? content;
      if (Platform.isWindows) {
        String fileStr = "${_getWindowsSettingsDir()}\\app_settings.json";
        if (File(fileStr).existsSync()) {
          content = await File(fileStr).readAsString();
        }
      } else {
        final settingsUri = await getSettingsFolderUri();
        if (settingsUri == null) return;
        var file = await saf.child(settingsUri, 'app_settings.json');
        if (file != null) {
          final bytes = await saf.getDocumentContent(file.uri);
          if (bytes != null) content = utf8.decode(bytes);
        }
      }

      if (content != null) {
        Map<String, dynamic> decoded = jsonDecode(content);
        currentLayoutSetting = decoded["layout"] ?? "HL";
        globalShopName = decoded["shopName"] ?? "RETAIL INVOICE";
        currentThemeSetting = decoded["theme"] ?? "LIGHT";
      }
    } catch (e) {
      debugPrint("Error loading app configuration: $e");
    }
  }

  static Future<Uri?> getBackupsFolderUri() async {
    if (Platform.isWindows) return null;
    final baseUri = await getBaseFolderUri();
    if (baseUri == null) return null;
    var folder = await saf.child(baseUri, "INVENTORY BACKUPS");
    if (folder == null) {
      var doc = await saf.createDirectory(baseUri, "INVENTORY BACKUPS");
      return doc?.uri;
    }
    return folder.uri;
  }

  static Future<Uri?> getMyBillsFolderUri() async {
    if (Platform.isWindows) return null;
    final baseUri = await getBaseFolderUri();
    if (baseUri == null) return null;
    var folder = await saf.child(baseUri, "MYBILLS");
    if (folder == null) {
      var doc = await saf.createDirectory(baseUri, "MYBILLS");
      return doc?.uri;
    }
    return folder.uri;
  }

  static Future<Uri?> getAccountsFolderUri() async {
    if (Platform.isWindows) return null;
    final baseUri = await getBaseFolderUri();
    if (baseUri == null) return null;
    var folder = await saf.child(baseUri, "ACCOUNTS");
    if (folder == null) {
      var doc = await saf.createDirectory(baseUri, "ACCOUNTS");
      return doc?.uri;
    }
    return folder.uri;
  }
}

// --- CLOUD DATABASE HELPER (PER-USER FIRESTORE SYNC) ---
class CloudDatabase {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  // Sync inventory data to Firestore under the current user's UID
  static Future<void> syncInventoryToCloud() async {
    if (currentFirebaseUser == null) return;
    try {
      final uid = currentFirebaseUser!.uid;
      // Convert the inventory map to a JSON-safe format for Firestore
      Map<String, dynamic> inventoryData = {};
      globalInventory.forEach((key, value) {
        inventoryData[key] = value
            .map((item) => Map<String, String>.from(item))
            .toList();
      });
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('data')
          .doc('inventory')
          .set({
            '_version': 2,
            'inventory': inventoryData,
            'categoryColors': globalCategoryColors,
            'categoryOrder': globalInventory.keys.toList(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("Error syncing inventory to cloud: $e");
    }
  }

  // Load inventory data from Firestore for the current user
  static Future<void> loadInventoryFromCloud() async {
    if (currentFirebaseUser == null) return;
    try {
      final uid = currentFirebaseUser!.uid;
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('data')
          .doc('inventory')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        if (data.containsKey('_version') && data['_version'] == 2) {
          if (data['inventory'] != null) {
            Map<String, dynamic> decoded = Map<String, dynamic>.from(
              data['inventory'],
            );
            Map<String, List<Map<String, String>>> loadedInventory = {};
            decoded.forEach((key, value) {
              loadedInventory[key] = (value as List)
                  .map((item) => Map<String, String>.from(item))
                  .toList();
            });
            if (data.containsKey('categoryOrder') &&
                data['categoryOrder'] != null) {
              List<String> order = List<String>.from(data['categoryOrder']);
              Map<String, List<Map<String, String>>> orderedInventory = {};
              for (String cat in order) {
                if (loadedInventory.containsKey(cat)) {
                  orderedInventory[cat] = loadedInventory[cat]!;
                  loadedInventory.remove(cat);
                }
              }
              orderedInventory.addAll(loadedInventory);
              globalInventory = orderedInventory;
            } else {
              globalInventory = loadedInventory;
            }
          }
          if (data['categoryColors'] != null) {
            Map<String, dynamic> colors = Map<String, dynamic>.from(
              data['categoryColors'],
            );
            globalCategoryColors = colors.map(
              (key, value) => MapEntry(key, value.toString()),
            );
          }
        } else {
          if (data['inventory'] != null) {
            Map<String, dynamic> decoded = Map<String, dynamic>.from(
              data['inventory'],
            );
            Map<String, List<Map<String, String>>> loadedInventory = {};
            decoded.forEach((key, value) {
              loadedInventory[key] = (value as List)
                  .map((item) => Map<String, String>.from(item))
                  .toList();
            });
            globalInventory = loadedInventory;
            globalCategoryColors = {};
          }
        }

        // Also save to local disk so offline works
        await LocalDatabase.saveToDisk();
      }
    } catch (e) {
      debugPrint("Error loading inventory from cloud: $e");
    }
  }

  // Sync all settings to Firestore under the current user's UID
  static Future<void> syncSettingsToCloud() async {
    if (currentFirebaseUser == null) return;
    try {
      final uid = currentFirebaseUser!.uid;
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('data')
          .doc('settings')
          .set({
            'layout': currentLayoutSetting,
            'shopName': globalShopName,
            'theme': currentThemeSetting,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("Error syncing settings to cloud: $e");
    }
  }

  // Load all settings from Firestore for the current user
  static Future<void> loadSettingsFromCloud() async {
    if (currentFirebaseUser == null) return;
    try {
      final uid = currentFirebaseUser!.uid;
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('data')
          .doc('settings')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        currentLayoutSetting = data['layout'] ?? "HL";
        globalShopName = data['shopName'] ?? "RETAIL INVOICE";
        currentThemeSetting = data['theme'] ?? "LIGHT";
        // Also save to local disk
        await LocalDatabase.saveAppSettings();
      }
    } catch (e) {
      debugPrint("Error loading settings from cloud: $e");
    }
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  List<Map<String, dynamic>> _cart = [];
  bool _isLoadingDb = true;
  String? _selectedCategoryForGrid;

  // Keyboard shortcut state (Windows only)
  String _keyBuffer = "";
  bool _isEditComboMode = false;
  Timer? _keyDebounceTimer;
  final FocusNode _homeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndInit();
  }

  Future<void> _checkPermissionsAndInit() async {
    if (!Platform.isWindows) {
      final prefs = await SharedPreferences.getInstance();
      String? baseUriString = prefs.getString('settings_folder_uri');

      if (baseUriString == null ||
          !(await saf.isPersistedUri(Uri.parse(baseUriString)))) {
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text(
                "STORAGE REQUIRED",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              content: const Text(
                "Please select a folder to save your bills and inventory backups safely. We recommend to choose the 'Documents' folder.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "CHOOSE FOLDER",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }
        final uri = await saf.openDocumentTree(persistablePermission: true);
        if (uri != null) {
          await prefs.setString('settings_folder_uri', uri.toString());
        } else {
          return; // User cancelled
        }
      }
    }

    await LocalDatabase.loadFromDisk();
    await LocalDatabase.loadPartiesFromDisk();
    await LocalDatabase.loadAppSettings();

    try {
      currentFirebaseUser = FirebaseAuth.instance.currentUser;
      if (currentFirebaseUser == null) {
        // Attempt silent sign in if Firebase forgot the session but GoogleSignIn remembers it
        final googleSignIn = GoogleSignIn();
        final googleUser = await googleSignIn.signInSilently();
        if (googleUser != null) {
          final googleAuth = await googleUser.authentication;
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          final userCredential = await FirebaseAuth.instance
              .signInWithCredential(credential);
          currentFirebaseUser = userCredential.user;
        }
      }
    } catch (e) {
      debugPrint("Firebase auth error: $e");
    }

    smartBillingAppKey.currentState?.rebuildApp();
    setState(() {
      _isLoadingDb = false;
    });
  }

  Future<bool> _showConfirmationWarning(
    BuildContext context,
    String titleText,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext ctx) {
            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 48,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        titleText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blueGrey[100]
                              : Colors.blueGrey,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 25),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text(
                                  "YES",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text(
                                  "NO",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _generatePDF(String customerName, bool showRateColumn) async {
    if (_cart.isEmpty) return;
    final pdf = pw.Document();
    final now = DateTime.now();

    final displayDate = DateFormat('dd-MM-yyyy hh:mm a').format(now);
    final timeStampFormat = DateFormat('yyyyMMdd_HHmmss').format(now);

    final cleanCustomerName = customerName
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    final finalFileName = "${timeStampFormat}_$cleanCustomerName";

    double grandTotal = _cart.fold(0, (sum, item) => sum + item['total']);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Text(
                globalShopName.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 30),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  "NAME - $customerName",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  "DATE - $displayDate",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: showRateColumn
                  ? {
                      0: const pw.FixedColumnWidth(35),
                      1: const pw.FlexColumnWidth(3.0),
                      2: const pw.FixedColumnWidth(95),
                      3: const pw.FixedColumnWidth(110),
                      4: const pw.FixedColumnWidth(110),
                    }
                  : {
                      0: const pw.FixedColumnWidth(35),
                      1: const pw.FlexColumnWidth(3.5),
                      2: const pw.FixedColumnWidth(130),
                      3: const pw.FixedColumnWidth(145),
                    },
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Sr'),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Item'),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Qty'),
                    ),
                    if (showRateColumn)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('Rate'),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Total'),
                    ),
                  ],
                ),
                ...List.generate(_cart.length, (index) {
                  final item = _cart[index];
                  String rawEnglishName = item['name'] ?? "";
                  if (rawEnglishName.contains(" (")) {
                    rawEnglishName = rawEnglishName.split(" (").first;
                  }
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('${index + 1}'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(rawEnglishName),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('${item['qty']} ${item['unit']}'),
                      ),
                      if (showRateColumn)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Rs ${item['rate']}'),
                        ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          'Rs ${item['total'].toStringAsFixed(2)}',
                        ),
                      ),
                    ],
                  );
                }),
                pw.TableRow(
                  children: [
                    pw.SizedBox(),
                    pw.SizedBox(),
                    if (showRateColumn) pw.SizedBox(),
                    pw.Container(
                      alignment: pw.Alignment.centerRight,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        "GRAND TOTAL: ",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        "Rs ${grandTotal.toStringAsFixed(2)}",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    if (Platform.isWindows) {
      String baseDir = File(Platform.resolvedExecutable).parent.path;
      String dir = "$baseDir\\Billing APP\\MYBILLS";
      Directory(dir).createSync(recursive: true);
      File file = File("$dir\\$finalFileName.pdf");
      await file.writeAsBytes(await pdf.save());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Saved as $finalFileName.pdf")));
        setState(() => _cart = []);
      }
      return;
    }

    final pathUri = await LocalDatabase.getMyBillsFolderUri();
    if (pathUri != null) {
      await saf.createFileAsBytes(
        pathUri,
        mimeType: 'application/pdf',
        displayName: "$finalFileName.pdf",
        bytes: await pdf.save(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Saved as $finalFileName.pdf")));
        setState(() => _cart = []);
      }
    }
  }

  void _showCustomerNamePopup() {
    final TextEditingController nameController = TextEditingController();
    bool isNameTyped = false;
    bool globalShowRateSetting = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Focus(
        onKeyEvent: (node, event) {
          if (!Platform.isWindows) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.backspace &&
                HardwareKeyboard.instance.isShiftPressed) {
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: StatefulBuilder(
              builder: (context, setPopupState) {
                return Container(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "PLS ENTER THE NAME OF CUSTOMER",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blueGrey[100]
                              : Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        autofocus: true,
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (val) {
                          Navigator.pop(context);
                          _generatePDF(
                            val.trim().isEmpty ? "CASH" : val.trim(),
                            globalShowRateSetting,
                          );
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9\s\-.,()&/\\]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: "Enter Name (In English Only)...",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (val) {
                          setPopupState(() {
                            isNameTyped = val.trim().isNotEmpty;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => setPopupState(
                          () => globalShowRateSetting = !globalShowRateSetting,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "SHOW RATE COLUMN IN BILL",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.blueGrey[200]
                                      : Colors.blueGrey,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Checkbox(
                                value: globalShowRateSetting,
                                activeColor:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.blueGrey[400]
                                    : Colors.blueGrey[800],
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) => setPopupState(
                                  () => globalShowRateSetting = val ?? true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isNameTyped
                                      ? Colors.green
                                      : Colors.grey[300],
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: !isNameTyped
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _generatePDF(
                                          nameController.text.trim(),
                                          globalShowRateSetting,
                                        );
                                      },
                                child: const Text(
                                  "DONE",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text(
                                  "CANCEL",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _generatePDF("CASH", globalShowRateSetting);
                                },
                                child: const Text(
                                  "SKIP",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    List<Map<String, String>> matches = [];
    globalInventory.forEach((cat, items) {
      for (var item in items) {
        String baseName = item['name'] ?? "";
        String regionalName = item['regional_name'] ?? "";
        String combinedForSearch = regionalName.isNotEmpty
            ? "$baseName ($regionalName)"
            : baseName;
        if (combinedForSearch.toLowerCase().contains(query.toLowerCase()))
          matches.add(item);
      }
    });
    setState(() => _searchResults = matches);
  }

  void _showItemEntryPopup(Map<String, String> item, {int? editCartIndex}) {
    String localQty = editCartIndex != null
        ? _cart[editCartIndex]['qty'].toString()
        : "1";
    String masterUnit = item['unit'] ?? "Kg";
    String currentUnit = editCartIndex != null
        ? _cart[editCartIndex]['unit'].toString()
        : masterUnit;
    String localRate = editCartIndex != null
        ? _cart[editCartIndex]['rate'].toString()
        : (item['rate'] ?? "0");

    bool editingQty = true;
    bool isFirstTapQty = true;
    bool isFirstTapRate = true;

    String baseName = item['name'] ?? "";
    String regName = item['regional_name'] ?? "";
    String completeDisplayName = regName.isNotEmpty
        ? "$baseName ($regName)"
        : baseName;

    final FocusNode numpadFocusNode = FocusNode();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: StatefulBuilder(
          builder: (context, setPopupState) {
            List<String> allowedUnits = [];
            if (masterUnit == "Kg" || masterUnit == "GRAM")
              allowedUnits = ["Kg", "GRAM"];
            else if (masterUnit == "Ltr" || masterUnit == "ML")
              allowedUnits = ["Ltr", "ML"];
            else
              allowedUnits = ["PCS"];

            void handleNumpad(String val) {
              setPopupState(() {
                if (val == "DEL") {
                  if (editingQty) {
                    localQty = "0";
                    isFirstTapQty = true;
                  } else {
                    localRate = "0";
                    isFirstTapRate = true;
                  }
                } else if (val == ".") {
                  if (editingQty) {
                    if (!localQty.contains(".")) localQty += ".";
                  } else {
                    if (!localRate.contains(".")) localRate += ".";
                  }
                } else {
                  if (editingQty) {
                    if (isFirstTapQty || localQty == "0")
                      localQty = val;
                    else
                      localQty += val;
                    isFirstTapQty = false;
                  } else {
                    if (isFirstTapRate || localRate == "0")
                      localRate = val;
                    else
                      localRate += val;
                    isFirstTapRate = false;
                  }
                }
              });
            }

            void submitEntry() {
              double q = double.tryParse(localQty) ?? 0;
              double r = double.tryParse(localRate) ?? 0;

              if (q == 0 || r == 0) return;

              double total = 0.0;
              if (masterUnit == currentUnit) {
                total = q * r;
              } else if (masterUnit == "Kg" && currentUnit == "GRAM") {
                total = (q / 1000.0) * r;
              } else if (masterUnit == "GRAM" && currentUnit == "Kg") {
                total = (q * 1000.0) * r;
              } else if (masterUnit == "Ltr" && currentUnit == "ML") {
                total = (q / 1000.0) * r;
              } else if (masterUnit == "ML" && currentUnit == "Ltr") {
                total = (q * 1000.0) * r;
              } else {
                total = q * r;
              }

              setState(() {
                var entryData = {
                  'name': completeDisplayName,
                  'qty': localQty,
                  'rate': localRate,
                  'unit': currentUnit,
                  'total': total,
                };
                if (editCartIndex != null) {
                  _cart[editCartIndex] = entryData;
                } else {
                  _cart.add(entryData);
                }
                _searchController.clear();
                _searchResults = [];
                _selectedCategoryForGrid = null;
              });
              Navigator.pop(context);
            }

            return RawKeyboardListener(
              focusNode: numpadFocusNode..requestFocus(),
              onKey: (event) {
                if (event is RawKeyDownEvent) {
                  final key = event.logicalKey;
                  final isShift = HardwareKeyboard.instance.isShiftPressed;

                  if (Platform.isWindows) {
                    if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isShift) {
                        if (allowedUnits.length > 1) {
                          setPopupState(() {
                            currentUnit = currentUnit == allowedUnits[0]
                                ? allowedUnits[1]
                                : allowedUnits[0];
                          });
                        }
                      } else {
                        setPopupState(() => editingQty = true);
                      }
                      return;
                    }
                    if (key == LogicalKeyboardKey.arrowRight) {
                      if (isShift) {
                        if (allowedUnits.length > 1) {
                          setPopupState(() {
                            currentUnit = currentUnit == allowedUnits[0]
                                ? allowedUnits[1]
                                : allowedUnits[0];
                          });
                        }
                      } else {
                        setPopupState(() => editingQty = false);
                      }
                      return;
                    }
                    if (key == LogicalKeyboardKey.backspace) {
                      if (isShift) {
                        Navigator.pop(context);
                        return;
                      }
                    }
                    if (key == LogicalKeyboardKey.delete) {
                      if (isShift && editCartIndex != null) {
                        setState(() {
                          _cart.removeAt(editCartIndex);
                          _searchController.clear();
                          _searchResults = [];
                          _selectedCategoryForGrid = null;
                        });
                        Navigator.pop(context);
                        return;
                      }
                    }
                  }

                  if (key == LogicalKeyboardKey.digit0 ||
                      key == LogicalKeyboardKey.numpad0)
                    handleNumpad("0");
                  else if (key == LogicalKeyboardKey.digit1 ||
                      key == LogicalKeyboardKey.numpad1)
                    handleNumpad("1");
                  else if (key == LogicalKeyboardKey.digit2 ||
                      key == LogicalKeyboardKey.numpad2)
                    handleNumpad("2");
                  else if (key == LogicalKeyboardKey.digit3 ||
                      key == LogicalKeyboardKey.numpad3)
                    handleNumpad("3");
                  else if (key == LogicalKeyboardKey.digit4 ||
                      key == LogicalKeyboardKey.numpad4)
                    handleNumpad("4");
                  else if (key == LogicalKeyboardKey.digit5 ||
                      key == LogicalKeyboardKey.numpad5)
                    handleNumpad("5");
                  else if (key == LogicalKeyboardKey.digit6 ||
                      key == LogicalKeyboardKey.numpad6)
                    handleNumpad("6");
                  else if (key == LogicalKeyboardKey.digit7 ||
                      key == LogicalKeyboardKey.numpad7)
                    handleNumpad("7");
                  else if (key == LogicalKeyboardKey.digit8 ||
                      key == LogicalKeyboardKey.numpad8)
                    handleNumpad("8");
                  else if (key == LogicalKeyboardKey.digit9 ||
                      key == LogicalKeyboardKey.numpad9)
                    handleNumpad("9");
                  else if (key == LogicalKeyboardKey.period ||
                      key == LogicalKeyboardKey.numpadDecimal)
                    handleNumpad(".");
                  else if (key == LogicalKeyboardKey.backspace ||
                      key == LogicalKeyboardKey.delete)
                    handleNumpad("DEL");
                  else if (key == LogicalKeyboardKey.enter ||
                      key == LogicalKeyboardKey.numpadEnter)
                    submitEntry();
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              completeDisplayName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setPopupState(() {
                                editingQty = true;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? (editingQty
                                            ? Colors.blue[900]!.withOpacity(0.3)
                                            : Colors.blueGrey[900])
                                      : (editingQty
                                            ? Colors.blue[50]
                                            : Colors.grey[100]),
                                  border: Border.all(
                                    color: editingQty
                                        ? Colors.blue
                                        : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.blueGrey[700]!
                                              : Colors.grey.shade300),
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  children: [
                                    Text("QTY ($currentUnit)"),
                                    Text(
                                      localQty,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => setPopupState(() {
                                editingQty = false;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? (!editingQty
                                            ? Colors.blue[900]!.withOpacity(0.3)
                                            : Colors.blueGrey[900])
                                      : (!editingQty
                                            ? Colors.blue[50]
                                            : Colors.grey[100]),
                                  border: Border.all(
                                    color: !editingQty
                                        ? Colors.blue
                                        : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.blueGrey[700]!
                                              : Colors.grey.shade300),
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      "RATE (₹/$masterUnit)",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      localRate,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: allowedUnits
                            .map(
                              (u) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ChoiceChip(
                                  label: Text(
                                    u,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  selected: currentUnit == u,
                                  onSelected: (masterUnit == "PCS")
                                      ? null
                                      : (v) => setPopupState(
                                          () => currentUnit = u,
                                        ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 15),
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        childAspectRatio: 1.6,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children:
                            [
                                  "1",
                                  "2",
                                  "3",
                                  "4",
                                  "5",
                                  "6",
                                  "7",
                                  "8",
                                  "9",
                                  ".",
                                  "0",
                                  "DEL",
                                ]
                                .map(
                                  (e) => ElevatedButton(
                                    onPressed: () => handleNumpad(e),
                                    child: Text(
                                      e,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                ((double.tryParse(localQty) ?? 0) == 0 ||
                                    (double.tryParse(localRate) ?? 0) == 0)
                                ? Colors.grey[400]
                                : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed:
                              ((double.tryParse(localQty) ?? 0) == 0 ||
                                  (double.tryParse(localRate) ?? 0) == 0)
                              ? null
                              : submitEntry,
                          child: Text(
                            editCartIndex != null
                                ? "UPDATE TO BILL"
                                : "ADD TO BILL",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCartWidget(
    void Function(void Function()) setLocalState, {
    bool isDialog = false,
  }) {
    double cartTotal = _cart.fold(0, (sum, item) => sum + item['total']);
    return Container(
      padding: const EdgeInsets.all(15),
      color: isDialog ? null : Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "CURRENT BILL (${_cart.length} Items)",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isDialog)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
          const Divider(),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text("Cart is Empty"))
                : ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final cartItem = _cart[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 8,
                                child: InkWell(
                                  onTap: () {
                                    Map<String, String>? baseItemMatch;
                                    globalInventory.forEach((cat, items) {
                                      for (var item in items) {
                                        String baseName = item['name'] ?? "";
                                        String regName =
                                            item['regional_name'] ?? "";
                                        String testName = regName.isNotEmpty
                                            ? "$baseName ($regName)"
                                            : baseName;
                                        if (testName == cartItem['name'] ||
                                            baseName == cartItem['name'])
                                          baseItemMatch = item;
                                      }
                                    });

                                    baseItemMatch ??= {
                                      'name': cartItem['name'],
                                      'rate': cartItem['rate'],
                                      'unit': cartItem['unit'],
                                    };
                                    if (isDialog) Navigator.pop(context);
                                    _showItemEntryPopup(
                                      baseItemMatch!,
                                      editCartIndex: index,
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.blueGrey[800]
                                          : Colors.blueGrey[50],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          margin: const EdgeInsets.only(
                                            right: 8.0,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.blueGrey[600]
                                                : Colors.blueGrey[400],
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            "${index + 1}",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                cartItem['name'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                "${cartItem['qty']} ${cartItem['unit']} x ₹${cartItem['rate']}",
                                                style: TextStyle(
                                                  color:
                                                      Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.grey[300]
                                                      : Colors.grey[700],
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.red[900]!.withOpacity(0.4)
                                        : Colors.red[100],

                                    elevation: 0,
                                  ),
                                  onPressed: () async {
                                    bool
                                    confirm = await _showConfirmationWarning(
                                      context,
                                      "DO YOU REALLY WANT TO\nREMOVE THIS ITEM?",
                                    );
                                    if (confirm) {
                                      setState(() => _cart.removeAt(index));
                                      setLocalState(() {});
                                    }
                                  },
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                flex: 8,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _cart.isEmpty
                        ? null
                        : () {
                            if (isDialog) Navigator.pop(context);
                            _showCustomerNamePopup();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.blueGrey[700]
                          : Colors.blueGrey[900],
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      "GENERATE BILL (₹${cartTotal.toStringAsFixed(2)})",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _cart.isEmpty
                        ? null
                        : () async {
                            bool confirm = await _showConfirmationWarning(
                              context,
                              "DO YOU REALLY WANT TO\nCLEAR THE ENTIRE CART?",
                            );
                            if (confirm) {
                              setState(() => _cart = []);
                              if (isDialog && context.mounted)
                                Navigator.pop(context);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 1,
                    ),
                    child: const Icon(Icons.delete_sweep, size: 28),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCart() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setCartState) {
          return Dialog(child: _buildCartWidget(setCartState, isDialog: true));
        },
      ),
    );
  }

  Widget _buildSearchBarBoxOnly() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: "Search Item Name...",
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildSearchBarSection() {
    return Column(
      children: [
        _buildSearchBarBoxOnly(),
        Expanded(
          child: _searchResults.isEmpty
              ? const Center(
                  child: Text(
                    "Type to search items...",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    String baseName = _searchResults[index]['name'] ?? "";
                    String regName =
                        _searchResults[index]['regional_name'] ?? "";
                    String finalTitle = regName.isNotEmpty
                        ? "$baseName ($regName)"
                        : baseName;
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _searchResults[index]['color'] != null
                            ? parseHexColor(_searchResults[index]['color'])
                            : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.blueGrey[800]
                                  : Colors.blueGrey[50]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        title: Text(
                          finalTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _searchResults[index]['color'] != null
                                ? Colors.black87
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          "₹${_searchResults[index]['rate']} per ${_searchResults[index]['unit']}",
                          style: TextStyle(
                            color: _searchResults[index]['color'] != null
                                ? Colors.black87
                                : null,
                          ),
                        ),
                        onTap: () => _showItemEntryPopup(_searchResults[index]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryGridSection() {
    List<String> categories = globalInventory.keys.toList();
    if (categories.isEmpty) {
      return const Center(
        child: Text(
          "Warehouse Inventory Empty.\nAdd items in Settings.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: GridView.builder(
        itemCount: categories.length,
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemBuilder: (context, index) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: globalCategoryColors[categories[index]] != null
                  ? parseHexColor(globalCategoryColors[categories[index]])
                  : (isDark ? Colors.blueGrey[800] : Colors.blueGrey[50]),
              foregroundColor: globalCategoryColors[categories[index]] != null
                  ? Colors.black87
                  : (isDark ? Colors.white : Colors.blueGrey[900]),
              elevation: 1,

              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: () =>
                setState(() => _selectedCategoryForGrid = categories[index]),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (Platform.isWindows)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6.0),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[800],
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "${index + 1}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Text(
                  categories[index].toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryItemsView() {
    List<Map<String, String>> categoryItems =
        globalInventory[_selectedCategoryForGrid!] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.blueGrey),
                onPressed: () =>
                    setState(() => _selectedCategoryForGrid = null),
              ),
              Text(
                _selectedCategoryForGrid!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: categoryItems.isEmpty
              ? const Center(child: Text("No items found in this category."))
              : Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: GridView.builder(
                    itemCount: categoryItems.length,
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.2,
                        ),
                    itemBuilder: (context, index) {
                      final item = categoryItems[index];
                      String baseName = item['name'] ?? "";
                      String regName = item['regional_name'] ?? "";
                      String displayString = regName.isNotEmpty
                          ? "$baseName ($regName)"
                          : baseName;
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: item['color'] != null
                              ? parseHexColor(item['color'])
                              : (isDark
                                    ? Colors.orange[900]!.withOpacity(0.3)
                                    : Colors.orange[50]),
                          foregroundColor: item['color'] != null
                              ? Colors.black87
                              : (isDark
                                    ? Colors.orange[100]
                                    : Colors.blueGrey[900]),

                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: () => _showItemEntryPopup(item),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (Platform.isWindows)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6.0),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey[800],
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "${index + 1}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            Text(
                              displayString,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "₹${item['rate']}",
                              style: TextStyle(
                                color: item['color'] != null
                                    ? Colors.black87
                                    : (isDark
                                          ? Colors.orange[200]
                                          : Colors.blueGrey[600]),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMiddleLayout() {
    if (_selectedCategoryForGrid != null) return _buildCategoryItemsView();
    if (currentLayoutSetting == "SBL") return _buildSearchBarSection();
    if (currentLayoutSetting == "DGL") return _buildCategoryGridSection();

    if (_searchController.text.isEmpty) {
      return Column(
        children: [
          _buildSearchBarBoxOnly(),
          const Divider(height: 1, thickness: 1),
          Expanded(child: _buildCategoryGridSection()),
        ],
      );
    } else {
      return _buildSearchBarSection();
    }
  }

  Widget _buildMobileAppView(bool showBottomBar, double totalBill) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _homeFocusNode.requestFocus();
      },
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          Expanded(child: _buildMiddleLayout()),
          if (showBottomBar)
            Container(
              height: 75,
              color: Colors.blueGrey[900],
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: InkWell(
                      onTap: _showCart,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Badge(
                            label: Text(
                              _cart.length.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            backgroundColor: Colors.red,
                            isLabelVisible: _cart.isNotEmpty,
                            child: const Icon(
                              Icons.shopping_cart,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "CART",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: Text(
                        "TOTAL: ₹${totalBill.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!Platform.isWindows) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (FocusManager.instance.primaryFocus != _homeFocusNode) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.backspace) {
      if (_selectedCategoryForGrid != null) {
        setState(() => _selectedCategoryForGrid = null);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (isShift && _cart.isNotEmpty) {
        _showCustomerNamePopup();
        return KeyEventResult.handled;
      }
    }

    String char = event.character ?? '';
    if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
        key.keyId <= LogicalKeyboardKey.digit9.keyId) {
      char = (key.keyId - LogicalKeyboardKey.digit0.keyId).toString();
    } else if (key.keyId >= LogicalKeyboardKey.numpad0.keyId &&
        key.keyId <= LogicalKeyboardKey.numpad9.keyId) {
      char = (key.keyId - LogicalKeyboardKey.numpad0.keyId).toString();
    }

    if (char.isNotEmpty && RegExp(r'^[0-9]$').hasMatch(char)) {
      if (isShift) {
        _isEditComboMode = true;
      }
      _keyBuffer += char;
      _triggerDebounce();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _triggerDebounce() {
    _keyDebounceTimer?.cancel();
    _keyDebounceTimer = Timer(
      const Duration(milliseconds: 500),
      _executeShortcut,
    );
  }

  void _executeShortcut() {
    if (!mounted) return;
    if (_keyBuffer.isEmpty) {
      _isEditComboMode = false;
      return;
    }

    int index = int.tryParse(_keyBuffer) ?? 0;
    _keyBuffer = "";
    bool editMode = _isEditComboMode;
    _isEditComboMode = false;

    if (index == 0) return;

    if (editMode) {
      if (index <= _cart.length) {
        var cartItem = _cart[index - 1];
        Map<String, String>? baseItemMatch;
        globalInventory.forEach((cat, itemsList) {
          for (var item in itemsList) {
            String baseName = item['name'] ?? "";
            String regName = item['regional_name'] ?? "";
            String testName = regName.isNotEmpty
                ? "$baseName ($regName)"
                : baseName;
            if (testName == cartItem['name'] || baseName == cartItem['name']) {
              baseItemMatch = item;
            }
          }
        });
        baseItemMatch ??= {
          'name': cartItem['name'].toString(),
          'rate': cartItem['rate'].toString(),
          'unit': cartItem['unit'].toString(),
        };
        _showItemEntryPopup(baseItemMatch!, editCartIndex: index - 1);
      }
    } else {
      if (_selectedCategoryForGrid == null) {
        List<String> categories = globalInventory.keys.toList();
        if (index <= categories.length) {
          setState(() {
            _selectedCategoryForGrid = categories[index - 1];
          });
        }
      } else {
        List<Map<String, String>> categoryItems =
            globalInventory[_selectedCategoryForGrid!] ?? [];
        if (index <= categoryItems.length) {
          _showItemEntryPopup(categoryItems[index - 1]);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalBill = _cart.fold(0, (sum, item) => sum + item['total']);
    return Focus(
      autofocus: true,
      focusNode: _homeFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blueGrey[900],
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.build_circle, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SetupScreen()),
            ).then((_) => setState(() {})),
          ),
          title: const Text(
            "BILLING APP",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WarehouseScreen(),
                ),
              ).then((_) => setState(() {})),
            ),
          ],
        ),
        body: _isLoadingDb
            ? const Center(child: CircularProgressIndicator())
            : Platform.isWindows
            ? Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildMobileAppView(false, totalBill),
                  ),
                  Container(width: 1, color: Colors.grey.withOpacity(0.5)),
                  Expanded(
                    flex: 2,
                    child: _buildCartWidget(setState, isDialog: false),
                  ),
                ],
              )
            : _buildMobileAppView(true, totalBill),
      ),
    );
  }
}

// --- SETUP SCREEN ---
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        setState(() => _isSigningIn = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);

      setState(() {
        currentFirebaseUser = userCredential.user;
        _isSigningIn = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Signed in successfully! Use 'IMPORT FROM CLOUD' to sync data.",
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Signed in as ${currentFirebaseUser?.email ?? 'Unknown'}",
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSigningIn = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sign-in failed: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      debugPrint("Google Sign-In error: $e");
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      setState(() {
        currentFirebaseUser = null;
      });

      // Reload local data after sign-out
      await LocalDatabase.loadFromDisk();
      await LocalDatabase.loadAppSettings();
      smartBillingAppKey.currentState?.rebuildApp();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Signed out successfully"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Sign-out error: $e")));
      }
    }
  }

  // Internal logic to run an inventory save and return the written File handle (cached locally for sharing)
  Future<void> _exportAndShareFiles(
    bool shareInventory,
    bool shareSettings,
  ) async {
    try {
      List<XFile> filesToShare = [];
      final tempDir = Directory.systemTemp;

      if (Platform.isWindows) {
        String baseDir = File(Platform.resolvedExecutable).parent.path;
        String dir = "$baseDir\\Billing APP\\INVENTORY BACKUPS";
        Directory(dir).createSync(recursive: true);

        if (shareInventory) {
          final content = jsonEncode(globalInventory);
          final bytes = Uint8List.fromList(utf8.encode(content));
          File invFile = File("$dir\\inventory_data.json");
          await invFile.writeAsBytes(bytes);
          filesToShare.add(XFile(invFile.path));
        }

        if (shareSettings) {
          final content = jsonEncode({
            "layout": currentLayoutSetting,
            "shopName": globalShopName,
            "theme": currentThemeSetting,
          });
          final bytes = Uint8List.fromList(utf8.encode(content));
          File setFile = File("$dir\\app_settings.json");
          await setFile.writeAsBytes(bytes);
          filesToShare.add(XFile(setFile.path));
        }
      } else {
        final backupUri = await LocalDatabase.getBackupsFolderUri();
        if (backupUri == null) return;

        if (shareInventory) {
          var invFile = await saf.child(backupUri, 'inventory_data.json');
          final content = jsonEncode(globalInventory);
          final bytes = Uint8List.fromList(utf8.encode(content));
          if (invFile == null) {
            await saf.createFileAsBytes(
              backupUri,
              mimeType: 'application/json',
              displayName: 'inventory_data.json',
              bytes: bytes,
            );
          } else {
            await saf.writeToFileAsBytes(invFile.uri, bytes: bytes);
          }
          final tempInv = File("${tempDir.path}/inventory_data.json");
          await tempInv.writeAsBytes(bytes);
          filesToShare.add(XFile(tempInv.path));
        }

        if (shareSettings) {
          var setFile = await saf.child(backupUri, 'app_settings.json');
          final content = jsonEncode({
            "layout": currentLayoutSetting,
            "shopName": globalShopName,
            "theme": currentThemeSetting,
          });
          final bytes = Uint8List.fromList(utf8.encode(content));
          if (setFile == null) {
            await saf.createFileAsBytes(
              backupUri,
              mimeType: 'application/json',
              displayName: 'app_settings.json',
              bytes: bytes,
            );
          } else {
            await saf.writeToFileAsBytes(setFile.uri, bytes: bytes);
          }
          final tempSet = File("${tempDir.path}/app_settings.json");
          await tempSet.writeAsBytes(bytes);
          filesToShare.add(XFile(tempSet.path));
        }
      }

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(filesToShare, text: 'My Billing App Backup');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to share backup: $e")));
      }
    }
  }

  Future<void> _importLocalBackup(
    bool importInventory,
    bool importSettings,
  ) async {
    try {
      bool inventorySuccess = false;
      bool settingsSuccess = false;

      if (Platform.isWindows) {
        String baseDir = File(Platform.resolvedExecutable).parent.path;
        String dir = "$baseDir\\Billing APP\\INVENTORY BACKUPS";

        if (importInventory) {
          File invFile = File("$dir\\inventory_data.json");
          if (invFile.existsSync()) {
            final content = await invFile.readAsString();
            Map<String, dynamic> decoded = jsonDecode(content);
            Map<String, List<Map<String, String>>> verifiedInventory = {};
            decoded.forEach((key, value) {
              verifiedInventory[key] = (value as List)
                  .map((item) => Map<String, String>.from(item))
                  .toList();
            });
            globalInventory = verifiedInventory;
            await LocalDatabase.saveToDisk();
            inventorySuccess = true;
          } else {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Inventory backup file not found."),
                ),
              );
          }
        }

        if (importSettings) {
          File setFile = File("$dir\\app_settings.json");
          if (setFile.existsSync()) {
            final content = await setFile.readAsString();
            Map<String, dynamic> decoded = jsonDecode(content);
            currentLayoutSetting = decoded["layout"] ?? "HL";
            globalShopName = decoded["shopName"] ?? "RETAIL INVOICE";
            currentThemeSetting = decoded["theme"] ?? "LIGHT";
            await LocalDatabase.saveAppSettings();
            settingsSuccess = true;
          } else {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("App settings backup file not found."),
                ),
              );
          }
        }
      } else {
        final backupUri = await LocalDatabase.getBackupsFolderUri();
        if (backupUri == null) return;

        if (importInventory) {
          var invFile = await saf.child(backupUri, 'inventory_data.json');
          if (invFile != null) {
            final bytes = await saf.getDocumentContent(invFile.uri);
            if (bytes != null) {
              final content = utf8.decode(bytes);
              Map<String, dynamic> decoded = jsonDecode(content);
              Map<String, List<Map<String, String>>> verifiedInventory = {};
              decoded.forEach((key, value) {
                verifiedInventory[key] = (value as List)
                    .map((item) => Map<String, String>.from(item))
                    .toList();
              });
              globalInventory = verifiedInventory;
              await LocalDatabase.saveToDisk();
              inventorySuccess = true;
            }
          } else {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Inventory backup file not found."),
                ),
              );
          }
        }

        if (importSettings) {
          var setFile = await saf.child(backupUri, 'app_settings.json');
          if (setFile != null) {
            final bytes = await saf.getDocumentContent(setFile.uri);
            if (bytes != null) {
              final content = utf8.decode(bytes);
              Map<String, dynamic> decoded = jsonDecode(content);
              currentLayoutSetting = decoded["layout"] ?? "HL";
              globalShopName = decoded["shopName"] ?? "RETAIL INVOICE";
              currentThemeSetting = decoded["theme"] ?? "LIGHT";
              await LocalDatabase.saveAppSettings();
              settingsSuccess = true;
            }
          } else {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("App settings backup file not found."),
                ),
              );
          }
        }
      }

      if (inventorySuccess || settingsSuccess) {
        setState(() {});
        smartBillingAppKey.currentState?.rebuildApp();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Local import complete!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Local Backup Import Failed: $e")),
        );
      }
    }
  }

  Future<void> _showCenterBackupMenu() async {
    bool isVIP = false;
    bool hasInternet = await CloudDatabase.hasInternetConnection();
    if (currentFirebaseUser != null && currentFirebaseUser!.email != null) {
      if (hasInternet) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('app_config')
              .doc('whitelist')
              .get(const GetOptions(source: Source.serverAndCache));
          if (doc.exists) {
            final data = doc.data();
            if (data != null && data['allowed_emails'] is List) {
              List allowed = data['allowed_emails'];
              if (allowed.contains(currentFirebaseUser!.email)) {
                isVIP = true;
              }
            }
          }
        } catch (e) {
          debugPrint("Error checking VIP status: $e");
        }
      }
    }

    bool exportInventory = false;
    bool exportSettings = false;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool anySelected = exportInventory || exportSettings;
          return AlertDialog(
            title: const Center(
              child: Text(
                "BACKUP OPTIONS",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: exportInventory,
                          onChanged: (val) {
                            setDialogState(
                              () => exportInventory = val ?? false,
                            );
                          },
                        ),
                        const Text("INVENTORY", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: exportSettings,
                          onChanged: (val) {
                            setDialogState(() => exportSettings = val ?? false);
                          },
                        ),
                        const Text(
                          "APP SETTINGS",
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // --- ROW 1: EXPORT SYSTEM (80% / 20%) ---
                Row(
                  children: [
                    Expanded(
                      flex: 8,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: (!anySelected || !isVIP)
                              ? null
                              : () async {
                                  if (currentFirebaseUser == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Please sign in first!"),
                                      ),
                                    );
                                    return;
                                  }
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  Navigator.pop(context);

                                  if (!await CloudDatabase.hasInternetConnection()) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Failed: No internet connection!",
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text("Exporting to cloud..."),
                                    ),
                                  );
                                  if (exportInventory)
                                    await CloudDatabase.syncInventoryToCloud();
                                  if (exportSettings)
                                    await CloudDatabase.syncSettingsToCloud();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text("Export complete!"),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text(
                            "EXPORT TO CLOUD",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: Colors.grey[200],
                            disabledForegroundColor: Colors.grey[500],
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: !anySelected
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _exportAndShareFiles(
                                    exportInventory,
                                    exportSettings,
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: Colors.grey[200],
                            disabledForegroundColor: Colors.grey[500],
                            backgroundColor: Colors.blueGrey[100],
                            foregroundColor: Colors.blueGrey[900],
                            elevation: 1,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                          ),
                          child: const Icon(Icons.share, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.grey, thickness: 0.5),
                const SizedBox(height: 12),
                // --- ROW 2: IMPORT SYSTEM (80% / 20%) ---
                Row(
                  children: [
                    Expanded(
                      flex: 8,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: (!anySelected || !isVIP)
                              ? null
                              : () async {
                                  if (currentFirebaseUser == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Please sign in first!"),
                                      ),
                                    );
                                    return;
                                  }
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  Navigator.pop(context);

                                  if (!await CloudDatabase.hasInternetConnection()) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Failed: No internet connection!",
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text("Importing from cloud..."),
                                    ),
                                  );
                                  if (exportInventory)
                                    await CloudDatabase.loadInventoryFromCloud();
                                  if (exportSettings) {
                                    await CloudDatabase.loadSettingsFromCloud();
                                    smartBillingAppKey.currentState
                                        ?.rebuildApp();
                                  }
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text("Import complete!"),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text(
                            "IMPORT FROM CLOUD",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: Colors.grey[200],
                            disabledForegroundColor: Colors.grey[500],
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: !anySelected
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _importLocalBackup(
                                    exportInventory,
                                    exportSettings,
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: Colors.grey[200],
                            disabledForegroundColor: Colors.grey[500],
                            backgroundColor: Colors.blueGrey[100],
                            foregroundColor: Colors.blueGrey[900],
                            elevation: 1,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                          ),
                          child: const Icon(Icons.file_open, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (currentFirebaseUser == null) ...[
                  Text(
                    "SIGN-IN TO USE CLOUD SYNC",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.yellow[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else if (!hasInternet) ...[
                  Text(
                    "CONNECT TO INTERNET TO USE CLOUD SYNC",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.yellow[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else if (isVIP) ...[
                  const Text(
                    "Hurray!! YOU ARE VIP USER",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "YOU CAN FREELY USE CLOUD SYNC",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else ...[
                  const Text(
                    "SORRY , YOU ARE NOT VIP USER",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "TO BECOME VIP USER CONTACT",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "SHRINIVAS PHUKE OR SOHAM INDURKAR",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAppSettingsMenu() {
    String tempShopName = globalShopName;
    String tempTheme = currentThemeSetting;
    String tempLayout = currentLayoutSetting;
    final TextEditingController shopNameController = TextEditingController(
      text: tempShopName,
    );

    void showUnsavedWarning() {
      showDialog(
        context: context,
        builder: (warnContext) => AlertDialog(
          title: const Text(
            "UNSAVED CHANGES",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "You have unsaved changes. Are you sure you want to close without saving?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(warnContext), // close warning
              child: const Text(
                "CANCEL",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(warnContext); // close warning
                Navigator.pop(context); // close app settings menu
              },
              child: const Text(
                "DISCARD",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setPopupState) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "APP SETTINGS",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        "SHOP NAME ( Will be displayed at top in BILL)",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: shopNameController,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9 ]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: "Enter Shop Name",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 15,
                          ),
                        ),
                        onChanged: (val) {
                          tempShopName = val;
                        },
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        "THEME",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setPopupState(() => tempTheme = "LIGHT"),
                              child: Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  color: tempTheme == "LIGHT"
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: tempTheme == "LIGHT"
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(
                                      Icons.wb_sunny,
                                      size: 40,
                                      color: Colors.black12,
                                    ),
                                    Text(
                                      "LIGHT",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: tempTheme == "LIGHT"
                                            ? Colors.blue
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setPopupState(() => tempTheme = "DARK"),
                              child: Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  color: tempTheme == "DARK"
                                      ? Colors.indigo.withOpacity(0.1)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: tempTheme == "DARK"
                                        ? Colors.indigo
                                        : Colors.grey,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(
                                      Icons.nightlight_round,
                                      size: 40,
                                      color: Colors.black12,
                                    ),
                                    Text(
                                      "DARK",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: tempTheme == "DARK"
                                            ? Colors.indigo
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        "LAYOUT",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Column(
                        children: [
                          _buildLayoutOption(
                            title: "SEARCH BAR LAYOUT",
                            icon: Icons.search,
                            layoutCode: "SBL",
                            currentSelection: tempLayout,
                            onTap: () =>
                                setPopupState(() => tempLayout = "SBL"),
                          ),
                          const SizedBox(height: 8),
                          _buildLayoutOption(
                            title: "DIRECT GRID LAYOUT",
                            icon: Icons.grid_view,
                            layoutCode: "DGL",
                            currentSelection: tempLayout,
                            onTap: () =>
                                setPopupState(() => tempLayout = "DGL"),
                          ),
                          const SizedBox(height: 8),
                          _buildLayoutOption(
                            title: "HYBRID LAYOUT",
                            icon: Icons.dashboard_customize,
                            layoutCode: "HL",
                            currentSelection: tempLayout,
                            onTap: () => setPopupState(() => tempLayout = "HL"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[200],
                                foregroundColor: Colors.black87,
                              ),
                              onPressed: () {
                                if (tempShopName != globalShopName ||
                                    tempTheme != currentThemeSetting ||
                                    tempLayout != currentLayoutSetting) {
                                  showUnsavedWarning();
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text(
                                "CLOSE",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                String entry = shopNameController.text.trim();
                                globalShopName = entry.isEmpty
                                    ? "RETAIL INVOICE"
                                    : entry.toUpperCase();
                                currentThemeSetting = tempTheme;
                                currentLayoutSetting = tempLayout;
                                await LocalDatabase.saveAppSettings();
                                if (mounted) {
                                  Navigator.pop(context);
                                  smartBillingAppKey.currentState?.rebuildApp();
                                }
                              },
                              child: const Text(
                                "SAVE",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLayoutOption({
    required String title,
    required IconData icon,
    required String layoutCode,
    required String currentSelection,
    required VoidCallback onTap,
  }) {
    bool isSelected = currentSelection == layoutCode;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? Colors.blue.withOpacity(0.05)
              : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.blue : null,
                ),
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "SETUP & SETTINGS",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            InkWell(
              onTap: _isSigningIn
                  ? null
                  : (currentFirebaseUser == null
                        ? _handleGoogleSignIn
                        : _handleSignOut),
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: currentFirebaseUser == null
                      ? (isDark ? Colors.blueGrey[800] : Colors.blueGrey[50])
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: currentFirebaseUser == null
                        ? (isDark
                              ? Colors.blueGrey[700]!
                              : Colors.blueGrey.shade200)
                        : Colors.green,
                  ),
                ),
                child: Center(
                  child: _isSigningIn
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (currentFirebaseUser == null)
                                  const Icon(Icons.login, size: 20)
                                else
                                  const Icon(
                                    Icons.check_circle,
                                    size: 20,
                                    color: Colors.green,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  currentFirebaseUser == null
                                      ? "SIGN-IN WITH GOOGLE"
                                      : "SIGNED IN",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: currentFirebaseUser == null
                                        ? null
                                        : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            if (currentFirebaseUser != null)
                              Text(
                                "${currentFirebaseUser!.email?.toLowerCase() ?? 'user'} (TAP TO LOGOUT)",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  color: Colors.green,
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: _showAppSettingsMenu,
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: isDark ? Colors.blueGrey[800] : Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.blueGrey[700]!
                        : Colors.blueGrey.shade200,
                  ),
                ),
                child: const Center(
                  child: Text(
                    "APP SETTINGS",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: _showCenterBackupMenu,
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: isDark ? Colors.blueGrey[800] : Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.blueGrey[700]!
                        : Colors.blueGrey.shade200,
                  ),
                ),
                child: const Center(
                  child: Text(
                    "INVENTORY BACKUP",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Placeholder removed
            const Center(
              child: Text(
                "COMPLETELY DESIGNED AND MADE BY SOHAM INDURKAR",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// --- WAREHOUSE SCREEN ---
class WarehouseScreen extends StatelessWidget {
  const WarehouseScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "WAREHOUSE",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CategoriesScreen(),
                  ),
                ),
                icon: const Icon(Icons.inventory_2),
                label: const Text("INVENTORY"),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.blueGrey[800]
                      : Colors.blueGrey[50],
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.blueGrey[900],
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LedgerScreen()),
                ),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text("ACCOUNTING"),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.blueGrey[800]
                      : Colors.blueGrey[50],
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.blueGrey[900],
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("PDF HISTORY"),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.blueGrey[800]
                      : Colors.blueGrey[50],
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.blueGrey[900],
                ),
              ),
            ),
            const Spacer(),
            const Center(
              child: Text(
                "COMPLETELY DESIGNED AND MADE BY SOHAM INDURKAR",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// --- HISTORY SCREEN ---
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _allPdfFiles = [];
  List<dynamic> _filteredPdfFiles = [];
  final TextEditingController _historySearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (Platform.isWindows) {
      String baseDir = File(Platform.resolvedExecutable).parent.path;
      String dir = "$baseDir\\Billing APP\\MYBILLS";
      Directory myBillsDir = Directory(dir);
      if (myBillsDir.existsSync()) {
        List<File> loadedFiles = myBillsDir
            .listSync()
            .where((e) => e is File && e.path.endsWith('.pdf'))
            .map((e) => e as File)
            .toList();

        loadedFiles.sort((a, b) {
          final aDate = a.lastModifiedSync();
          final bDate = b.lastModifiedSync();
          return bDate.compareTo(aDate);
        });

        setState(() {
          _allPdfFiles = loadedFiles;
          _filteredPdfFiles = loadedFiles;
        });
      }
      return;
    }

    final uri = await LocalDatabase.getMyBillsFolderUri();
    if (uri != null) {
      final stream = saf.listFiles(
        uri,
        columns: [
          saf.DocumentFileColumn.displayName,
          saf.DocumentFileColumn.lastModified,
          saf.DocumentFileColumn.size,
        ],
      );
      List<saf.DocumentFile> loadedFiles = [];

      await for (var doc in stream) {
        if (doc.name != null && doc.name!.endsWith('.pdf')) {
          loadedFiles.add(doc);
        }
      }

      loadedFiles.sort((a, b) {
        final aDate = a.lastModified ?? DateTime(2000);
        final bDate = b.lastModified ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });

      setState(() {
        _allPdfFiles = loadedFiles;
        _filteredPdfFiles = loadedFiles;
      });
    }
  }

  void _historySearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredPdfFiles = _allPdfFiles;
      });
      return;
    }
    setState(() {
      _filteredPdfFiles = _allPdfFiles.where((file) {
        String name = file is File
            ? file.path.split(Platform.pathSeparator).last
            : (file as saf.DocumentFile).name ?? "";
        String printableName = _parseInvoiceNameForDisplay(name).toLowerCase();
        return printableName.contains(query.toLowerCase());
      }).toList();
    });
  }

  String _parseInvoiceNameForDisplay(String fullPath) {
    try {
      final rawName = fullPath
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.pdf', '');
      final parts = rawName.split('_');
      if (parts.length >= 3 && parts[0].length == 8 && parts[1].length == 6) {
        String rawDate = parts[0];
        String rawTime = parts[1];
        String formattedName = parts.sublist(2).join(' ');
        String displayDate =
            "${rawDate.substring(6, 8)}-${rawDate.substring(4, 6)}-${rawDate.substring(0, 4)}";
        int hour = int.parse(rawTime.substring(0, 2));
        String minute = rawTime.substring(2, 4);
        String second = rawTime.substring(4, 6);
        String period = hour >= 12 ? "PM" : "AM";
        int displayHour = hour % 12;
        if (displayHour == 0) displayHour = 12;
        String displayTime =
            "${displayHour.toString().padLeft(2, '0')}:$minute:$second $period";
        return "$formattedName $displayDate $displayTime";
      }
    } catch (e) {
      debugPrint("Parsing configuration mismatch detected: $e");
    }
    return fullPath.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "BILL HISTORY",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LedgerHistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text(
                  "LEDGER",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.blueGrey[800]
                      : Colors.blueGrey[50],
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.blueGrey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            child: TextField(
              controller: _historySearchController,
              onChanged: _historySearchChanged,
              decoration: InputDecoration(
                hintText: "Search Invoice Name...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _historySearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _historySearchController.clear();
                          _historySearchChanged("");
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: _filteredPdfFiles.isEmpty
                ? const Center(
                    child: Text(
                      "No records found.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredPdfFiles.length,
                    itemBuilder: (context, index) {
                      final file = _filteredPdfFiles[index];
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                              vertical: 2.0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 85,
                                  child: Container(
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.blueGrey[800]
                                          : Colors.blueGrey[50],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        try {
                                          if (file is File) {
                                            OpenFilex.open(file.path);
                                          } else {
                                            final safFile =
                                                file as saf.DocumentFile;
                                            final bytes = await saf
                                                .getDocumentContent(
                                                  safFile.uri,
                                                );
                                            if (bytes != null) {
                                              final tempFile = File(
                                                '${Directory.systemTemp.path}/${safFile.name}',
                                              );
                                              await tempFile.writeAsBytes(
                                                bytes,
                                              );
                                              OpenFilex.open(tempFile.path);
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint("Error opening file: $e");
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.picture_as_pdf,
                                              color: Colors.red,
                                              size: 28,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                _parseInvoiceNameForDisplay(
                                                  file is File
                                                      ? file.path
                                                            .split(
                                                              Platform
                                                                  .pathSeparator,
                                                            )
                                                            .last
                                                      : (file as saf.DocumentFile)
                                                                .name ??
                                                            "Unknown",
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13.5,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 15,
                                  child: Container(
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.blueGrey[700]
                                          : Colors.blueGrey[100],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        try {
                                          if (file is File) {
                                            Share.shareXFiles([
                                              XFile(file.path),
                                            ], text: 'Invoice Sharing');
                                          } else {
                                            final safFile =
                                                file as saf.DocumentFile;
                                            final bytes = await saf
                                                .getDocumentContent(
                                                  safFile.uri,
                                                );
                                            if (bytes != null) {
                                              final tempFile = File(
                                                '${Directory.systemTemp.path}/${safFile.name}',
                                              );
                                              await tempFile.writeAsBytes(
                                                bytes,
                                              );
                                              Share.shareXFiles([
                                                XFile(tempFile.path),
                                              ], text: 'Invoice Sharing');
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint("Error sharing file: $e");
                                        }
                                      },
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.share,
                                            color: isDark
                                                ? Colors.blueGrey[100]
                                                : Colors.blueGrey,
                                            size: 20,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "SHARE",
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.blueGrey[100]
                                                  : Colors.blueGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 1),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- HISTORY SCREEN ---
class LedgerHistoryScreen extends StatefulWidget {
  const LedgerHistoryScreen({super.key});
  @override
  State<LedgerHistoryScreen> createState() => _LedgerHistoryScreenState();
}

class _LedgerHistoryScreenState extends State<LedgerHistoryScreen> {
  List<dynamic> _allPdfFiles = [];
  List<dynamic> _filteredPdfFiles = [];
  final TextEditingController _historySearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (Platform.isWindows) {
      String baseDir = File(Platform.resolvedExecutable).parent.path;
      String dir = "$baseDir\\Billing APP\\ACCOUNTS";
      Directory myBillsDir = Directory(dir);
      if (myBillsDir.existsSync()) {
        List<File> loadedFiles = myBillsDir
            .listSync()
            .where((e) => e is File && e.path.endsWith('.pdf'))
            .map((e) => e as File)
            .toList();

        loadedFiles.sort((a, b) {
          final aDate = a.lastModifiedSync();
          final bDate = b.lastModifiedSync();
          return bDate.compareTo(aDate);
        });

        setState(() {
          _allPdfFiles = loadedFiles;
          _filteredPdfFiles = loadedFiles;
        });
      }
      return;
    }

    final uri = await LocalDatabase.getAccountsFolderUri();
    if (uri != null) {
      final stream = saf.listFiles(
        uri,
        columns: [
          saf.DocumentFileColumn.displayName,
          saf.DocumentFileColumn.lastModified,
          saf.DocumentFileColumn.size,
        ],
      );
      List<saf.DocumentFile> loadedFiles = [];

      await for (var doc in stream) {
        if (doc.name != null && doc.name!.endsWith('.pdf')) {
          loadedFiles.add(doc);
        }
      }

      loadedFiles.sort((a, b) {
        final aDate = a.lastModified ?? DateTime(2000);
        final bDate = b.lastModified ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });

      setState(() {
        _allPdfFiles = loadedFiles;
        _filteredPdfFiles = loadedFiles;
      });
    }
  }

  void _historySearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredPdfFiles = _allPdfFiles;
      });
      return;
    }
    setState(() {
      _filteredPdfFiles = _allPdfFiles.where((file) {
        String name = file is File
            ? file.path.split(Platform.pathSeparator).last
            : (file as saf.DocumentFile).name ?? "";
        String printableName = _parseInvoiceNameForDisplay(name).toLowerCase();
        return printableName.contains(query.toLowerCase());
      }).toList();
    });
  }

  String _parseInvoiceNameForDisplay(String fullPath) {
    try {
      final rawName = fullPath
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.pdf', '');
      final parts = rawName.split('_');
      if (parts.length >= 3 && parts[0].length == 8 && parts[1].length == 6) {
        String rawDate = parts[0];
        String rawTime = parts[1];
        String formattedName = parts.sublist(2).join(' ');
        String displayDate =
            "${rawDate.substring(6, 8)}-${rawDate.substring(4, 6)}-${rawDate.substring(0, 4)}";
        int hour = int.parse(rawTime.substring(0, 2));
        String minute = rawTime.substring(2, 4);
        String second = rawTime.substring(4, 6);
        String period = hour >= 12 ? "PM" : "AM";
        int displayHour = hour % 12;
        if (displayHour == 0) displayHour = 12;
        String displayTime =
            "${displayHour.toString().padLeft(2, '0')}:$minute:$second $period";
        return "$formattedName $displayDate $displayTime";
      }
    } catch (e) {
      debugPrint("Parsing configuration mismatch detected: $e");
    }
    return fullPath.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "LEDGER HISTORY",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _historySearchController,
              onChanged: _historySearchChanged,
              decoration: InputDecoration(
                hintText: "Search Invoice Name...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _historySearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _historySearchController.clear();
                          _historySearchChanged("");
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: _filteredPdfFiles.isEmpty
                ? const Center(
                    child: Text(
                      "No records found.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredPdfFiles.length,
                    itemBuilder: (context, index) {
                      final file = _filteredPdfFiles[index];
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                              vertical: 2.0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 85,
                                  child: Container(
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.blueGrey[800]
                                          : Colors.blueGrey[50],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        try {
                                          if (file is File) {
                                            OpenFilex.open(file.path);
                                          } else {
                                            final safFile =
                                                file as saf.DocumentFile;
                                            final bytes = await saf
                                                .getDocumentContent(
                                                  safFile.uri,
                                                );
                                            if (bytes != null) {
                                              final tempFile = File(
                                                '${Directory.systemTemp.path}/${safFile.name}',
                                              );
                                              await tempFile.writeAsBytes(
                                                bytes,
                                              );
                                              OpenFilex.open(tempFile.path);
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint("Error opening file: $e");
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.picture_as_pdf,
                                              color: Colors.red,
                                              size: 28,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                _parseInvoiceNameForDisplay(
                                                  file is File
                                                      ? file.path
                                                            .split(
                                                              Platform
                                                                  .pathSeparator,
                                                            )
                                                            .last
                                                      : (file as saf.DocumentFile)
                                                                .name ??
                                                            "Unknown",
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13.5,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 15,
                                  child: Container(
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.blueGrey[700]
                                          : Colors.blueGrey[100],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        try {
                                          if (file is File) {
                                            Share.shareXFiles([
                                              XFile(file.path),
                                            ], text: 'Invoice Sharing');
                                          } else {
                                            final safFile =
                                                file as saf.DocumentFile;
                                            final bytes = await saf
                                                .getDocumentContent(
                                                  safFile.uri,
                                                );
                                            if (bytes != null) {
                                              final tempFile = File(
                                                '${Directory.systemTemp.path}/${safFile.name}',
                                              );
                                              await tempFile.writeAsBytes(
                                                bytes,
                                              );
                                              Share.shareXFiles([
                                                XFile(tempFile.path),
                                              ], text: 'Invoice Sharing');
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint("Error sharing file: $e");
                                        }
                                      },
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.share,
                                            color: isDark
                                                ? Colors.blueGrey[100]
                                                : Colors.blueGrey,
                                            size: 20,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "SHARE",
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.blueGrey[100]
                                                  : Colors.blueGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 1),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- CATEGORIES SCREEN ---
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _catC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _catC.addListener(() => setState(() {}));
  }

  Future<bool> _showWarning(String msg) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 48,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                "YES",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text(
                                "NO",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  void _onReorderCategories(int oldIndex, int newIndex) async {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      List<String> keys = globalInventory.keys.toList();
      final String movedKey = keys.removeAt(oldIndex);
      keys.insert(newIndex, movedKey);
      Map<String, List<Map<String, String>>> sortedMap = {};
      for (var key in keys) {
        sortedMap[key] = globalInventory[key]!;
      }
      globalInventory = sortedMap;
    });
    await LocalDatabase.saveToDisk();
  }

  @override
  Widget build(BuildContext context) {
    List<String> names = globalInventory.keys.toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("CATEGORIES", style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 8,
                  child: TextField(
                    controller: _catC,
                    decoration: const InputDecoration(
                      hintText: "Category Name",
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _catC.text.trim().isEmpty
                        ? null
                        : () async {
                            String? color = await showColorPickerDialog(
                              context,
                              null,
                            );
                            if (color != null) {
                              String catName = _catC.text.trim();
                              if (catName.isNotEmpty) {
                                globalInventory[catName] = [];
                                globalCategoryColors[catName] = color;
                                await LocalDatabase.saveToDisk();
                                setState(() {});
                              }
                              _catC.clear();
                            }
                          },
                    child: const Text("ADD"),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: names.length,
              onReorder: _onReorderCategories,
              itemBuilder: (context, i) {
                return Padding(
                  key: ValueKey("category_row_${names[i]}"),
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(Icons.menu, color: Colors.orange),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(right: 8.0),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey[800],
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "${i + 1}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            backgroundColor:
                                globalCategoryColors[names[i]] != null
                                ? parseHexColor(globalCategoryColors[names[i]])
                                : null,
                            foregroundColor:
                                globalCategoryColors[names[i]] != null
                                ? Colors.black87
                                : null,
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ItemDetailScreen(categoryName: names[i]),
                            ),
                          ).then((_) => setState(() {})),
                          child: Text(names[i]),
                        ),
                      ),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () async {
                          String oldName = names[i];
                          TextEditingController nameCtrl =
                              TextEditingController(text: oldName);
                          String? newColor = await showColorPickerDialog(
                            context,
                            globalCategoryColors[oldName],
                            isEditing: true,
                            categoryNameController: nameCtrl,
                          );
                          if (newColor != null) {
                            setState(() {
                              String newName = nameCtrl.text.trim();
                              if (newName.isNotEmpty && newName != oldName) {
                                if (!globalInventory.containsKey(newName)) {
                                  Map<String, List<Map<String, String>>>
                                  newInventory = {};
                                  for (String key in globalInventory.keys) {
                                    if (key == oldName) {
                                      newInventory[newName] =
                                          globalInventory[oldName] ?? [];
                                    } else {
                                      newInventory[key] = globalInventory[key]!;
                                    }
                                  }
                                  globalInventory = newInventory;
                                  globalCategoryColors[newName] = newColor;
                                  globalCategoryColors.remove(oldName);
                                } else {
                                  globalCategoryColors[oldName] = newColor;
                                }
                              } else {
                                globalCategoryColors[oldName] = newColor;
                              }
                            });
                            await LocalDatabase.saveToDisk();
                          }
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: parseHexColor(
                              globalCategoryColors[names[i]],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white54
                                  : Colors.black26,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.red[900]!.withOpacity(0.4)
                                : Colors.red[100],
                          ),
                          onPressed: () async {
                            bool confirm = await _showWarning(
                              "ARE YOU SURE YOU WANT TO\nDELETE THIS CATEGORY?",
                            );
                            if (confirm) {
                              globalInventory.remove(names[i]);
                              await LocalDatabase.saveToDisk();
                              setState(() {});
                            }
                          },
                          child: const Icon(Icons.delete, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- ITEM DETAIL SCREEN ---
class ItemDetailScreen extends StatefulWidget {
  final String categoryName;
  const ItemDetailScreen({super.key, required this.categoryName});
  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final TextEditingController _englishNameController = TextEditingController();
  final TextEditingController _regionalNameController = TextEditingController();
  final TextEditingController _r = TextEditingController();
  String? _selectedUnit;
  int? _editingIndex;
  String _selectedColor = presetColors.first;

  bool get _isValid =>
      _englishNameController.text.trim().isNotEmpty &&
      _r.text.trim().isNotEmpty &&
      _selectedUnit != null;

  Future<bool> _showWarning(String msg) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 48,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                "YES",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text(
                                "NO",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  @override
  void initState() {
    super.initState();
    _englishNameController.addListener(() => setState(() {}));
    _regionalNameController.addListener(() => setState(() {}));
    _r.addListener(() => setState(() {}));
  }

  void _onReorderItems(int oldIndex, int newIndex) async {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      var items = globalInventory[widget.categoryName]!;
      final movedItem = items.removeAt(oldIndex);
      items.insert(newIndex, movedItem);
    });
    await LocalDatabase.saveToDisk();
  }

  Widget _buildUnitSelectionButton(String unitLabel) {
    bool isCurrent = _selectedUnit == unitLabel;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: SizedBox(
        height: 45,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isCurrent
                ? (isDark ? Colors.blueGrey[200] : Colors.blueGrey[800])
                : (isDark ? Colors.blueGrey[800] : Colors.blueGrey[50]),
            foregroundColor: isCurrent
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? Colors.white : Colors.blueGrey[900]),
            elevation: isCurrent ? 2 : 0,

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isCurrent
                    ? Colors.transparent
                    : (isDark
                          ? Colors.blueGrey[700]!
                          : Colors.blueGrey.shade200),
              ),
            ),
          ),
          onPressed: () => setState(() => _selectedUnit = unitLabel),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                unitLabel,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: unitLabel == "GRAM" ? 10 : 11,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 2),
                const Icon(Icons.check, size: 11, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var items = globalInventory[widget.categoryName]!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _englishNameController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9\s\-.,()&/\\]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        hintText: "In English Only",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _regionalNameController,
                      decoration: const InputDecoration(
                        hintText: "In Regional language",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _r,
                    decoration: const InputDecoration(
                      hintText: "Rate",
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildUnitSelectionButton("Kg"),
                        _buildUnitSelectionButton("Ltr"),
                        _buildUnitSelectionButton("PCS"),
                        _buildUnitSelectionButton("GRAM"),
                        _buildUnitSelectionButton("ML"),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    String? newColor = await showColorPickerDialog(
                      context,
                      _selectedColor,
                      isEditing: _editingIndex != null,
                    );
                    if (newColor != null) {
                      setState(() {
                        _selectedColor = newColor;
                      });
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: parseHexColor(_selectedColor),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white54
                            : Colors.blueGrey,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _editingIndex == null
                            ? Colors.green
                            : Colors.orange,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      onPressed: !_isValid
                          ? null
                          : () async {
                              var data = {
                                'name': _englishNameController.text.trim(),
                                'regional_name': _regionalNameController.text
                                    .trim(),
                                'rate': _r.text.trim(),
                                'unit': _selectedUnit!,
                                'color': _selectedColor,
                              };
                              if (_editingIndex == null) {
                                items.add(data);
                              } else {
                                items[_editingIndex!] = data;
                                _editingIndex = null;
                              }
                              await LocalDatabase.saveToDisk();
                              _englishNameController.clear();
                              _regionalNameController.clear();
                              _r.clear();
                              _selectedUnit = null;
                              _selectedColor = presetColors.first;
                              setState(() {});
                            },
                      child: Text(
                        _editingIndex == null ? "ADD ITEM" : "SAVE CHANGES",
                        style: TextStyle(
                          color: _isValid ? Colors.white : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 30),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: items.length,
                onReorder: _onReorderItems,
                itemBuilder: (context, i) {
                  bool isEditing = _editingIndex == i;
                  String baseName = items[i]['name'] ?? "";
                  String regName = items[i]['regional_name'] ?? "";
                  String formattedDisplayName = regName.isNotEmpty
                      ? "$baseName ($regName)"
                      : baseName;
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;

                  return Padding(
                    key: ValueKey("item_row_${items[i]['name']}_$i"),
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(Icons.menu, color: Colors.orange),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(right: 8.0),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isEditing
                                ? Colors.orange[800]
                                : (isDark
                                      ? Colors.blueGrey[600]
                                      : Colors.blueGrey[400]),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "${i + 1}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 8,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _editingIndex = i;
                                        _englishNameController.text =
                                            items[i]['name'] ?? "";
                                        _regionalNameController.text =
                                            items[i]['regional_name'] ?? "";
                                        _r.text = items[i]['rate'] ?? "";
                                        _selectedUnit = items[i]['unit']!;
                                        _selectedColor =
                                            items[i]['color'] ??
                                            presetColors.first;
                                      });
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isEditing
                                            ? (isDark
                                                  ? Colors.orange[900]!
                                                        .withOpacity(0.3)
                                                  : Colors.orange[50])
                                            : (items[i]['color'] != null
                                                  ? parseHexColor(
                                                      items[i]['color'],
                                                    )
                                                  : (isDark
                                                        ? Colors.blueGrey[800]
                                                        : Colors.blueGrey[50])),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            formattedDisplayName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            "₹${items[i]['rate']}/${items[i]['unit']}",
                                            style: TextStyle(
                                              color: items[i]['color'] != null
                                                  ? Colors.black87
                                                  : (isDark
                                                        ? Colors.grey[300]
                                                        : Colors.grey[700]),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isEditing
                                          ? (isDark
                                                ? Colors.blueGrey[900]
                                                : Colors.grey[200])
                                          : (isDark
                                                ? Colors.red[900]!.withOpacity(
                                                    0.4,
                                                  )
                                                : Colors.red[100]),
                                    ),
                                    onPressed: isEditing
                                        ? null
                                        : () async {
                                            bool confirm = await _showWarning(
                                              "ARE YOU SURE YOU WANT TO\nDELETE THIS ITEM?",
                                            );
                                            if (confirm) {
                                              items.removeAt(i);
                                              await LocalDatabase.saveToDisk();
                                              setState(() {});
                                            }
                                          },
                                    child: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- LEDGER SCREEN ---
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});
  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  String _searchQuery = "";

  void _onReorderParties(int oldIndex, int newIndex) {
    if (_searchQuery.isNotEmpty) return;
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = globalParties.removeAt(oldIndex);
      globalParties.insert(newIndex, item);
    });
    LocalDatabase.savePartiesToDisk();
  }

  Future<bool> _showWarning(String msg) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 48,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[500],
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text(
                                "CANCEL",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                "DELETE",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  void _showPartyConfigurationPopup() {
    final nameController = TextEditingController();
    final dateController = TextEditingController();
    final balanceController = TextEditingController();
    bool isDebit = true;
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final RegExp dateRegExp = RegExp(
              r'^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[0-2])-\d{4}$',
            );

            bool isDateValid = dateRegExp.hasMatch(dateController.text.trim());
            bool isNameValid = nameController.text.trim().isNotEmpty;
            bool isBalanceValid = balanceController.text.trim().isNotEmpty;
            bool allValid = isDateValid && isNameValid && isBalanceValid;

            void checkFields() {
              setDialogState(() {});
            }

            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Platform.isWindows ? 400 : double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "PARTY CONFIGURATION",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.blueGrey[100]
                              : Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: nameController,
                        onChanged: (_) => checkFields(),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: "Name of Party",
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: dateController,
                        onChanged: (_) => checkFields(),
                        keyboardType: TextInputType.datetime,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: "OPENING DATE (DD-MM-YYYY)",
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: balanceController,
                        onChanged: (_) => checkFields(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          hintText: "OPENING BALANCE",
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDebit
                                      ? (isDark
                                            ? Colors.blueGrey[200]
                                            : Colors.blueGrey[800])
                                      : (isDark
                                            ? Colors.blueGrey[800]
                                            : Colors.blueGrey[50]),
                                  foregroundColor: isDebit
                                      ? (isDark ? Colors.black : Colors.white)
                                      : (isDark
                                            ? Colors.white
                                            : Colors.blueGrey[900]),
                                  elevation: isDebit ? 2 : 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isDebit
                                          ? Colors.transparent
                                          : (isDark
                                                ? Colors.blueGrey[700]!
                                                : Colors.blueGrey.shade200),
                                    ),
                                  ),
                                ),
                                onPressed: () =>
                                    setDialogState(() => isDebit = true),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "DEBIT",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (isDebit) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.check,
                                        size: 12,
                                        color: isDark
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: !isDebit
                                      ? (isDark
                                            ? Colors.blueGrey[200]
                                            : Colors.blueGrey[800])
                                      : (isDark
                                            ? Colors.blueGrey[800]
                                            : Colors.blueGrey[50]),
                                  foregroundColor: !isDebit
                                      ? (isDark ? Colors.black : Colors.white)
                                      : (isDark
                                            ? Colors.white
                                            : Colors.blueGrey[900]),
                                  elevation: !isDebit ? 2 : 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: !isDebit
                                          ? Colors.transparent
                                          : (isDark
                                                ? Colors.blueGrey[700]!
                                                : Colors.blueGrey.shade200),
                                    ),
                                  ),
                                ),
                                onPressed: () =>
                                    setDialogState(() => isDebit = false),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "CREDIT",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (!isDebit) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.check,
                                        size: 12,
                                        color: isDark
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: allValid
                                      ? Colors.green
                                      : Colors.grey.withOpacity(0.5),
                                  foregroundColor: allValid
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                                onPressed: !allValid
                                    ? null
                                    : () {
                                        setState(() {
                                          globalParties.add({
                                            'name': nameController.text.trim(),
                                            'opening_date': dateController.text
                                                .trim(),
                                            'opening_balance':
                                                double.tryParse(
                                                  balanceController.text.trim(),
                                                ) ??
                                                0.0,
                                            'opening_type': isDebit
                                                ? 'debit'
                                                : 'credit',
                                          });
                                        });
                                        LocalDatabase.savePartiesToDisk();

                                        nameController.clear();
                                        dateController.clear();
                                        balanceController.clear();
                                        checkFields();

                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              "Party added successfully!",
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      },
                                child: const Text(
                                  "ADD PARTY",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  if (allValid) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text("Warning"),
                                        content: const Text(
                                          "You have un-saved party details filled in. Are you sure you want to close?",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text("NO"),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(
                                                context,
                                              ); // close warning
                                              Navigator.pop(
                                                context,
                                              ); // close party popup
                                            },
                                            child: const Text(
                                              "YES, CLOSE",
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  } else {
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text(
                                  "CLOSE",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredParties = globalParties.where((p) {
      final pName = (p['name'] ?? "").toString().toLowerCase();
      return pName.contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey[800],
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "PARTIES",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _showPartyConfigurationPopup,
                    icon: const Icon(Icons.add_circle),
                    label: const Text(
                      "ADD PARTY",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: "Search Parties...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blueGrey[800]
                        : Colors.blueGrey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (globalParties.isNotEmpty) const Divider(height: 1, thickness: 1),
          Expanded(
            child: filteredParties.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? "No parties match your search."
                          : "No parties found. Click ADD PARTY above.",
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: filteredParties.length,
                    onReorder: _onReorderParties,
                    itemBuilder: (context, i) {
                      final party = filteredParties[i];
                      final pName = party['name'] ?? "Unknown";
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;

                      // Find original global index for display if needed, but we can just use `i` for visual list rank, or global rank.
                      // It makes sense to display the global rank number even when searching.
                      final globalIndex = globalParties.indexOf(party);

                      return Padding(
                        key: ValueKey("party_row_${globalIndex}_$pName"),
                        padding: const EdgeInsets.only(
                          top: 8.0,
                          left: 8.0,
                          right: 8.0,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _searchQuery.isNotEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 4.0,
                                        ),
                                        child: Icon(
                                          Icons.menu,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : ReorderableDragStartListener(
                                        index: i,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 4.0,
                                          ),
                                          child: Icon(
                                            Icons.menu,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ),
                                Container(
                                  margin: const EdgeInsets.only(
                                    right: 8.0,
                                    left: 4.0,
                                  ),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.blueGrey[800]
                                        : Colors.blueGrey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "${globalIndex + 1}",
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.blueGrey[900],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PartyLedgerScreen(
                                                partyIndex: globalIndex,
                                              ),
                                        ),
                                      ).then((_) => setState(() {}));
                                    },
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.blueGrey[800]
                                            : Colors.blueGrey[50],
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ),
                                      child: Text(
                                        pName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 48,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        backgroundColor: isDark
                                            ? Colors.red[900]!.withOpacity(0.4)
                                            : Colors.red[100],
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      onPressed: () async {
                                        bool confirm = await _showWarning(
                                          "Are you sure you want to delete '$pName'? This action cannot be undone.",
                                        );
                                        if (confirm) {
                                          setState(() {
                                            globalParties.remove(party);
                                          });
                                          await LocalDatabase.savePartiesToDisk();
                                        }
                                      },
                                      child: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, thickness: 1),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- PARTY LEDGER SCREEN ---
class PartyLedgerScreen extends StatefulWidget {
  final int partyIndex;

  const PartyLedgerScreen({super.key, required this.partyIndex});

  @override
  State<PartyLedgerScreen> createState() => _PartyLedgerScreenState();
}

class _PartyLedgerScreenState extends State<PartyLedgerScreen> {
  final _amountCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  String _selectedType = 'PAYMENT';

  int _viewMonth = DateTime.now().month;
  int _viewYear = DateTime.now().year;

  bool _isCustomMode = false;
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _isAllMode = false;

  Map<String, dynamic>? _editingTransaction;
  bool _isEditingOpening = false;

  static const _months = [
    "JAN",
    "FEB",
    "MAR",
    "APR",
    "MAY",
    "JUN",
    "JUL",
    "AUG",
    "SEP",
    "OCT",
    "NOV",
    "DEC",
  ];

  Widget _buildToggleBtn(String label, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 21,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: isSelected
              ? (isDark ? Colors.blueGrey[200] : Colors.blueGrey[800])
              : (isDark ? Colors.blueGrey[800] : Colors.blueGrey[50]),
          foregroundColor: isSelected
              ? (isDark ? Colors.black : Colors.white)
              : (isDark ? Colors.white : Colors.blueGrey[900]),
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? Colors.transparent
                  : (isDark ? Colors.blueGrey[700]! : Colors.blueGrey.shade200),
            ),
          ),
        ),
        onPressed: () => setState(() => _selectedType = label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 8),
            ),
            if (isSelected) ...[
              const SizedBox(width: 1),
              Icon(
                Icons.check,
                size: 8,
                color: isDark ? Colors.black : Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }

  DateTime? _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (e) {
      return null;
    }
  }

  Future<bool> _showUnsavedWarning() async {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Platform.isWindows ? 400 : double.infinity,
            ),
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "UNSAVED CHANGES",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "You have unsaved changes. Are you sure you want to close without saving?",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(
                            "CANCEL",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            "DISCARD",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _generateLedgerPDF({
    required Map<String, dynamic> party,
    required List<dynamic> displayedTransactions,
    required bool isOriginalOpening,
    required double displayOpeningVal,
    required String displayOpeningType,
    required String displayOpeningDate,
    required bool isBeforePartyOpening,
    required double totalDebit,
    required double totalCredit,
    required double grandTotal,
    required bool isDebitBigger,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();

    final displayDate = DateFormat('dd-MM-yyyy hh:mm a').format(now);
    final timeStampFormat = DateFormat('yyyyMMdd_HHmmss').format(now);

    final String partyName = party['name'] ?? 'Unknown';
    final cleanCustomerName = partyName
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    final finalFileName = "${timeStampFormat}_$cleanCustomerName";

    List<pw.TableRow> tableRows = [];

    tableRows.add(
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'SR NO.',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'DATE',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'DEBIT',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              'CREDIT',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (!isBeforePartyOpening) {
      tableRows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text('OPENING'),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                displayOpeningDate,
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                (displayOpeningType == 'debit' && displayOpeningVal > 0)
                    ? displayOpeningVal.toStringAsFixed(2)
                    : '',
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                (displayOpeningType == 'credit' && displayOpeningVal > 0)
                    ? displayOpeningVal.toStringAsFixed(2)
                    : '',
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    for (int i = 0; i < displayedTransactions.length; i++) {
      final t = displayedTransactions[i];
      final date = t['date'] ?? '';
      final debitVal = t['debit'] ?? 0.0;
      final creditVal = t['credit'] ?? 0.0;
      final debitStr = debitVal > 0 ? debitVal.toStringAsFixed(2) : '';
      final creditStr = creditVal > 0 ? creditVal.toStringAsFixed(2) : '';
      int displayIndex = isBeforePartyOpening ? i : i + 1;

      tableRows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text('$displayIndex'),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(date, textAlign: pw.TextAlign.center),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(debitStr, textAlign: pw.TextAlign.center),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(creditStr, textAlign: pw.TextAlign.center),
            ),
          ],
        ),
      );
    }

    String gtLabel = totalDebit == totalCredit
        ? "0.00"
        : "${isDebitBigger ? 'DEBIT' : 'CREDIT'} - ${grandTotal.toStringAsFixed(2)}";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Text(
                globalShopName.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 30),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  "NAME - $partyName",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  "DATE - $displayDate",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.0),
                1: const pw.FlexColumnWidth(3.0),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(2.5),
              },
              children: tableRows,
            ),
            pw.Table(
              border: pw.TableBorder(
                left: const pw.BorderSide(),
                right: const pw.BorderSide(),
                bottom: const pw.BorderSide(),
                verticalInside: const pw.BorderSide(),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(5.0),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FlexColumnWidth(2.5),
              },
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'TOTAL :-',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        totalDebit.toStringAsFixed(2),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        totalCredit.toStringAsFixed(2),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Table(
              border: pw.TableBorder(
                left: const pw.BorderSide(),
                right: const pw.BorderSide(),
                bottom: const pw.BorderSide(),
                verticalInside: const pw.BorderSide(),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(5.0),
                1: const pw.FlexColumnWidth(5.0),
              },
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'GRAND TOTAL :-',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        gtLabel,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    if (Platform.isWindows) {
      String baseDir = File(Platform.resolvedExecutable).parent.path;
      String dir = "$baseDir\\Billing APP\\ACCOUNTS";
      Directory(dir).createSync(recursive: true);
      File file = File("$dir\\$finalFileName.pdf");
      await file.writeAsBytes(await pdf.save());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Saved as $finalFileName.pdf")));
      }
      return;
    }

    final pathUri = await LocalDatabase.getAccountsFolderUri();
    if (pathUri != null) {
      await saf.createFileAsBytes(
        pathUri,
        mimeType: 'application/pdf',
        displayName: "$finalFileName.pdf",
        bytes: await pdf.save(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Saved as $finalFileName.pdf")));
      }
    }
  }

  void _showDeleteTransactionDialog(
    Map<String, dynamic> party,
    Map<String, dynamic> transactionToRemove,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Platform.isWindows ? 400 : double.infinity,
            ),
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "WARNING",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "Are you sure you want to delete this transaction?",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () async {
                            setState(() {
                              List tList = party['transactions'];
                              tList.remove(transactionToRemove);
                            });
                            await LocalDatabase.savePartiesToDisk();
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "YES, DELETE",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "CANCEL",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCustomRangePopup() {
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final RegExp dateRegExp = RegExp(
              r'^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[0-2])-\d{4}$',
            );
            bool isValid =
                fromCtrl.text.isNotEmpty &&
                toCtrl.text.isNotEmpty &&
                dateRegExp.hasMatch(fromCtrl.text.trim()) &&
                dateRegExp.hasMatch(toCtrl.text.trim());

            if (isValid) {
              DateTime? fromD = _parseDate(fromCtrl.text.trim());
              DateTime? toD = _parseDate(toCtrl.text.trim());
              if (fromD != null && toD != null && fromD.isAfter(toD)) {
                isValid = false;
              }
            }

            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Platform.isWindows ? 400 : double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: fromCtrl,
                        onChanged: (_) => setDialogState(() {}),
                        keyboardType: TextInputType.datetime,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: "FROM (In DD-MM-YYYY)",
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: toCtrl,
                        onChanged: (_) => setDialogState(() {}),
                        keyboardType: TextInputType.datetime,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: "TO (In DD-MM-YYYY)",
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isValid
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              onPressed: !isValid
                                  ? null
                                  : () {
                                      setState(() {
                                        _isCustomMode = true;
                                        _customFrom = _parseDate(
                                          fromCtrl.text.trim(),
                                        );
                                        _customTo = _parseDate(
                                          toCtrl.text.trim(),
                                        );
                                      });
                                      Navigator.pop(context);
                                    },
                              child: const Text(
                                "NEXT",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                "CLOSE",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.partyIndex >= globalParties.length) return const Scaffold();
    final party = globalParties[widget.partyIndex];
    final pName = party['name'] ?? "Unknown";

    if (party['transactions'] == null) {
      party['transactions'] = <Map<String, dynamic>>[];
    }
    List transactions = party['transactions'];

    transactions.sort((a, b) {
      DateTime d1 = _parseDate(a['date'] ?? '') ?? DateTime(1900);
      DateTime d2 = _parseDate(b['date'] ?? '') ?? DateTime(1900);
      return d1.compareTo(d2);
    });

    DateTime? partyOpenDate = _parseDate(party['opening_date'] ?? "");
    if (partyOpenDate == null) partyOpenDate = DateTime.now();

    double runningTotalDebit = 0.0;
    double runningTotalCredit = 0.0;

    final double ob = (party['opening_balance'] ?? 0.0).toDouble();
    final String ot = party['opening_type'] ?? 'debit';

    bool isBeforePartyOpening = false;
    if (_isAllMode) {
      isBeforePartyOpening = false;
    } else if (!_isCustomMode) {
      isBeforePartyOpening =
          _viewYear < partyOpenDate.year ||
          (_viewYear == partyOpenDate.year && _viewMonth < partyOpenDate.month);
    } else {
      isBeforePartyOpening =
          _customTo != null && _customTo!.isBefore(partyOpenDate);
    }

    bool isOriginalOpening = false;
    if (_isAllMode) {
      isOriginalOpening = true;
    } else if (!_isCustomMode) {
      isOriginalOpening =
          _viewMonth == partyOpenDate.month && _viewYear == partyOpenDate.year;
    } else {
      isOriginalOpening =
          _customFrom != null && !_customFrom!.isAfter(partyOpenDate);
    }

    if (!isBeforePartyOpening && !isOriginalOpening) {
      if (ot == 'debit')
        runningTotalDebit += ob;
      else
        runningTotalCredit += ob;
    }

    List displayedTransactions = [];

    for (var t in transactions) {
      DateTime? d = _parseDate(t['date'] ?? '');
      if (d == null) continue;

      if (_isAllMode) {
        displayedTransactions.add(t);
      } else if (_isCustomMode) {
        if (d.isBefore(_customFrom!)) {
          runningTotalDebit += (t['debit'] ?? 0.0);
          runningTotalCredit += (t['credit'] ?? 0.0);
        } else if (!d.isAfter(_customTo!)) {
          displayedTransactions.add(t);
        }
      } else {
        if (d.year < _viewYear ||
            (d.year == _viewYear && d.month < _viewMonth)) {
          runningTotalDebit += (t['debit'] ?? 0.0);
          runningTotalCredit += (t['credit'] ?? 0.0);
        } else if (d.year == _viewYear && d.month == _viewMonth) {
          displayedTransactions.add(t);
        }
      }
    }

    double carryForwardVal = (runningTotalDebit - runningTotalCredit).abs();
    String carryForwardType = runningTotalDebit >= runningTotalCredit
        ? 'debit'
        : 'credit';

    String displayOpeningDate = '';
    if (isOriginalOpening) {
      displayOpeningDate = party['opening_date'] ?? '';
    } else {
      if (_isCustomMode) {
        displayOpeningDate =
            "${_customFrom!.day.toString().padLeft(2, '0')}-${_customFrom!.month.toString().padLeft(2, '0')}-${_customFrom!.year}";
      } else {
        displayOpeningDate =
            '01-${_viewMonth.toString().padLeft(2, '0')}-$_viewYear';
      }
    }

    double displayOpeningVal = isOriginalOpening ? ob : carryForwardVal;
    String displayOpeningType = isOriginalOpening ? ot : carryForwardType;

    double totalDebit = 0.0;
    double totalCredit = 0.0;
    if (!isBeforePartyOpening) {
      if (displayOpeningType == 'debit')
        totalDebit += displayOpeningVal;
      else
        totalCredit += displayOpeningVal;

      for (var t in displayedTransactions) {
        totalDebit += (t['debit'] ?? 0.0);
        totalCredit += (t['credit'] ?? 0.0);
      }
    }

    double grandTotal = (totalDebit - totalCredit).abs();
    bool isDebitBigger = totalDebit >= totalCredit;
    Color grandTotalColor = totalDebit == totalCredit
        ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black)
        : (isDebitBigger ? Colors.green : Colors.red);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    bool isValidAdd = false;
    if (_amountCtrl.text.isNotEmpty && _dateCtrl.text.isNotEmpty) {
      final RegExp dateRegExp = RegExp(
        r'^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[0-2])-\d{4}$',
      );
      if (dateRegExp.hasMatch(_dateCtrl.text.trim())) {
        DateTime? enteredDate = _parseDate(_dateCtrl.text.trim());
        DateTime? openingDate = _parseDate(party['opening_date'] ?? "");
        if (enteredDate != null) {
          if (_isEditingOpening) {
            isValidAdd = true;
          } else if (openingDate == null ||
              !enteredDate.isBefore(openingDate)) {
            isValidAdd = true;
          }
        }
      }
    }

    bool isFormChanged = false;
    double currentAmt = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    String currentDate = _dateCtrl.text.trim();

    if (_isEditingOpening) {
      double origAmt =
          double.tryParse(party['opening_balance']?.toString() ?? "0.0") ?? 0.0;
      String origDate = party['opening_date'] ?? '';
      String origType = party['opening_type'] ?? 'PAYMENT';
      if (currentAmt != origAmt ||
          currentDate != origDate ||
          _selectedType != origType) {
        isFormChanged = true;
      }
    } else if (_editingTransaction != null) {
      double origDebit =
          double.tryParse(_editingTransaction!['debit']?.toString() ?? "0.0") ??
          0.0;
      double origCredit =
          double.tryParse(
            _editingTransaction!['credit']?.toString() ?? "0.0",
          ) ??
          0.0;
      String origDate = _editingTransaction!['date'] ?? '';
      String origType =
          _editingTransaction!['type'] ??
          (origDebit > 0 ? 'PAYMENT' : 'RECEIPT');
      double origAmt = origDebit > 0 ? origDebit : origCredit;
      if (currentAmt != origAmt ||
          currentDate != origDate ||
          _selectedType != origType) {
        isFormChanged = true;
      }
    } else {
      if (_amountCtrl.text.trim().isNotEmpty ||
          _dateCtrl.text.trim().isNotEmpty) {
        isFormChanged = true;
      }
    }

    bool canSave = isValidAdd && isFormChanged;

    return WillPopScope(
      onWillPop: () async {
        if (canSave) {
          return await _showUnsavedWarning();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blueGrey[800],
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              if (canSave) {
                bool discard = await _showUnsavedWarning();
                if (discard && mounted) {
                  Navigator.pop(context);
                }
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: const Text(
            "LEDGER",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            const SizedBox(height: 10),
            Text(
              "NAME - $pName",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 30,
                    child: SizedBox(
                      height: 45,
                      child: TextField(
                        controller: _amountCtrl,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          hintText: "AMOUNT",
                          hintStyle: TextStyle(fontSize: 10),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 30,
                    child: TextField(
                      controller: _dateCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: "DATE",
                        hintStyle: TextStyle(fontSize: 10),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 30,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildToggleBtn(
                                "PAYMENT",
                                _selectedType == 'PAYMENT',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildToggleBtn(
                                "RECEIPT",
                                _selectedType == 'RECEIPT',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: _buildToggleBtn(
                                "PURCHASE",
                                _selectedType == 'PURCHASE',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildToggleBtn(
                                "SALES",
                                _selectedType == 'SALES',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 10,
                    child: SizedBox(
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: canSave
                              ? Colors.green
                              : Colors.grey.withOpacity(0.5),
                          foregroundColor: canSave
                              ? Colors.white
                              : Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: !canSave
                            ? null
                            : () async {
                                setState(() {
                                  if (_isEditingOpening) {
                                    party['opening_balance'] =
                                        double.tryParse(
                                          _amountCtrl.text.trim(),
                                        ) ??
                                        0.0;
                                    party['opening_date'] = _dateCtrl.text
                                        .trim();
                                    party['opening_type'] = _selectedType;
                                  } else if (_editingTransaction != null) {
                                    bool toDebit =
                                        _selectedType == 'PAYMENT' ||
                                        _selectedType == 'SALES';
                                    _editingTransaction!['date'] = _dateCtrl
                                        .text
                                        .trim();
                                    _editingTransaction!['debit'] = toDebit
                                        ? (double.tryParse(
                                                _amountCtrl.text.trim(),
                                              ) ??
                                              0.0)
                                        : 0.0;
                                    _editingTransaction!['credit'] = !toDebit
                                        ? (double.tryParse(
                                                _amountCtrl.text.trim(),
                                              ) ??
                                              0.0)
                                        : 0.0;
                                    _editingTransaction!['type'] =
                                        _selectedType;

                                    transactions.sort((a, b) {
                                      DateTime dateA =
                                          _parseDate(a['date'] ?? "") ??
                                          DateTime(1970);
                                      DateTime dateB =
                                          _parseDate(b['date'] ?? "") ??
                                          DateTime(1970);
                                      return dateA.compareTo(dateB);
                                    });
                                  } else {
                                    bool toDebit =
                                        _selectedType == 'PAYMENT' ||
                                        _selectedType == 'SALES';
                                    transactions.add({
                                      'date': _dateCtrl.text.trim(),
                                      'debit': toDebit
                                          ? (double.tryParse(
                                                  _amountCtrl.text.trim(),
                                                ) ??
                                                0.0)
                                          : 0.0,
                                      'credit': !toDebit
                                          ? (double.tryParse(
                                                  _amountCtrl.text.trim(),
                                                ) ??
                                                0.0)
                                          : 0.0,
                                      'type': _selectedType,
                                    });
                                    transactions.sort((a, b) {
                                      DateTime dateA =
                                          _parseDate(a['date'] ?? "") ??
                                          DateTime(1970);
                                      DateTime dateB =
                                          _parseDate(b['date'] ?? "") ??
                                          DateTime(1970);
                                      return dateA.compareTo(dateB);
                                    });
                                  }
                                  _amountCtrl.clear();
                                  _dateCtrl.clear();
                                  _editingTransaction = null;
                                  _isEditingOpening = false;
                                });
                                await LocalDatabase.savePartiesToDisk();
                              },
                        child: Icon(
                          (_editingTransaction != null || _isEditingOpening)
                              ? Icons.save
                              : Icons.add,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              color: isDark ? Colors.blueGrey[900] : Colors.blueGrey[200],
              child: _isCustomMode
                  ? Row(
                      children: [
                        Text(
                          "CUSTOM RANGE : FROM ${_customFrom!.day.toString().padLeft(2, '0')}-${_customFrom!.month.toString().padLeft(2, '0')}-${_customFrom!.year} TO ${_customTo!.day.toString().padLeft(2, '0')}-${_customTo!.month.toString().padLeft(2, '0')}-${_customTo!.year}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _isCustomMode = false;
                              _viewMonth = DateTime.now().month;
                              _viewYear = DateTime.now().year;
                            });
                          },
                        ),
                      ],
                    )
                  : _isAllMode
                  ? Row(
                      children: [
                        const Text(
                          "ALL TRANSACTIONS",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _isAllMode = false;
                              _viewMonth = DateTime.now().month;
                              _viewYear = DateTime.now().year;
                            });
                          },
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "CURRENT MONTH : ${_months[_viewMonth - 1]} $_viewYear",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: Platform.isWindows
                                ? const EdgeInsets.symmetric(horizontal: 8)
                                : const EdgeInsets.all(8),
                            minimumSize: Platform.isWindows
                                ? Size.zero
                                : const Size(40, 40),
                            tapTargetSize: Platform.isWindows
                                ? MaterialTapTargetSize.shrinkWrap
                                : MaterialTapTargetSize.padded,
                            foregroundColor:
                                (_viewYear == partyOpenDate.year &&
                                    _viewMonth == partyOpenDate.month)
                                ? Colors.grey
                                : (isDark ? Colors.white : Colors.black),
                          ),
                          onPressed:
                              (_viewYear == partyOpenDate.year &&
                                  _viewMonth == partyOpenDate.month)
                              ? null
                              : () {
                                  setState(() {
                                    if (_viewMonth == 1) {
                                      _viewMonth = 12;
                                      _viewYear--;
                                    } else {
                                      _viewMonth--;
                                    }
                                  });
                                },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back_ios,
                                size: 14,
                                color:
                                    (_viewYear == partyOpenDate.year &&
                                        _viewMonth == partyOpenDate.month)
                                    ? Colors.grey
                                    : null,
                              ),
                              if (Platform.isWindows)
                                const Text(
                                  " PREVIOUS MONTH",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 2),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: Platform.isWindows
                                ? const EdgeInsets.symmetric(horizontal: 8)
                                : const EdgeInsets.all(8),
                            minimumSize: Platform.isWindows
                                ? Size.zero
                                : const Size(40, 40),
                            tapTargetSize: Platform.isWindows
                                ? MaterialTapTargetSize.shrinkWrap
                                : MaterialTapTargetSize.padded,
                            foregroundColor:
                                (_viewYear == DateTime.now().year &&
                                    _viewMonth == DateTime.now().month)
                                ? Colors.grey
                                : (isDark ? Colors.white : Colors.black),
                          ),
                          onPressed:
                              (_viewYear == DateTime.now().year &&
                                  _viewMonth == DateTime.now().month)
                              ? null
                              : () {
                                  setState(() {
                                    if (_viewMonth == 12) {
                                      _viewMonth = 1;
                                      _viewYear++;
                                    } else {
                                      _viewMonth++;
                                    }
                                  });
                                },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (Platform.isWindows)
                                const Text(
                                  "NEXT MONTH ",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color:
                                    (_viewYear == DateTime.now().year &&
                                        _viewMonth == DateTime.now().month)
                                    ? Colors.grey
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isAllMode = true;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 30),
                          ),
                          child: const Text(
                            "ALL",
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: _showCustomRangePopup,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 30),
                          ),
                          child: const Text(
                            "CUSTOM",
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _viewMonth = DateTime.now().month;
                              _viewYear = DateTime.now().year;
                            });
                          },
                        ),
                      ],
                    ),
            ),
            Container(
              color: isDark ? Colors.blueGrey[800] : Colors.blueGrey[100],
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 8.0,
              ),
              child: Row(
                children: const [
                  Expanded(
                    flex: 10,
                    child: Text(
                      "SR NO.",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 25,
                    child: Text(
                      "DATE",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 25,
                    child: Text(
                      "TYPE",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 15,
                    child: Text(
                      "DEBIT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 15,
                    child: Text(
                      "CREDIT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(flex: 10, child: SizedBox()),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount:
                    displayedTransactions.length +
                    (isBeforePartyOpening ? 0 : 1),
                itemBuilder: (context, i) {
                  if (!isBeforePartyOpening && i == 0) {
                    final String obDebit =
                        (displayOpeningType == 'debit' && displayOpeningVal > 0)
                        ? displayOpeningVal.toStringAsFixed(2)
                        : '';
                    final String obCredit =
                        (displayOpeningType == 'credit' &&
                            displayOpeningVal > 0)
                        ? displayOpeningVal.toStringAsFixed(2)
                        : '';
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 8.0,
                            left: 8.0,
                            right: 8.0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 85,
                                child: isOriginalOpening
                                    ? GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _isEditingOpening = true;
                                            _editingTransaction = null;
                                            _dateCtrl.text = displayOpeningDate;
                                            _amountCtrl.text =
                                                displayOpeningVal > 0
                                                ? displayOpeningVal
                                                      .toStringAsFixed(2)
                                                : '';
                                            _selectedType =
                                                party['opening_type'] ??
                                                'PAYMENT';
                                          });
                                        },
                                        child: Container(
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.blueGrey[800]
                                                : Colors.blueGrey[50],
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Expanded(
                                                flex: 10,
                                                child: Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4.0,
                                                  ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      "OPENING",
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 25,
                                                child: Text(
                                                  displayOpeningDate,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              const Expanded(
                                                flex: 25,
                                                child: Text(
                                                  "",
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 15,
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    obDebit,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 15,
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    obCredit,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : Container(
                                        height: 36,
                                        alignment: Alignment.center,
                                        child: Row(
                                          children: [
                                            const Expanded(
                                              flex: 10,
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 4.0,
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    "OPENING",
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 25,
                                              child: Text(
                                                displayOpeningDate,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            const Expanded(
                                              flex: 25,
                                              child: Text(
                                                "",
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 15,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  obDebit,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 15,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  obCredit,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              const Expanded(flex: 10, child: SizedBox()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: isDark
                              ? Colors.blueGrey[700]
                              : Colors.blueGrey.shade200,
                        ),
                      ],
                    );
                  }

                  final t =
                      displayedTransactions[isBeforePartyOpening ? i : i - 1];
                  final date = t['date'] ?? '';
                  final debitVal = t['debit'] ?? 0.0;
                  final creditVal = t['credit'] ?? 0.0;

                  final debitStr = debitVal > 0
                      ? debitVal.toStringAsFixed(2)
                      : '';
                  final creditStr = creditVal > 0
                      ? creditVal.toStringAsFixed(2)
                      : '';

                  final tType = t['type'] ?? '';
                  Color typeColor = isDark ? Colors.white : Colors.black;
                  if (tType == 'PAYMENT' || tType == 'PURCHASE') {
                    typeColor = Colors.red;
                  } else if (tType == 'RECEIPT' || tType == 'SALES') {
                    typeColor = Colors.green;
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 8.0,
                          left: 8.0,
                          right: 8.0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 85,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _editingTransaction = t;
                                    _isEditingOpening = false;
                                    _dateCtrl.text = date;
                                    _amountCtrl.text =
                                        (debitVal > 0 ? debitVal : creditVal)
                                            .toStringAsFixed(2);
                                    _selectedType =
                                        t['type'] ??
                                        (debitVal > 0 ? 'PAYMENT' : 'RECEIPT');
                                  });
                                },
                                child: Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.blueGrey[800]
                                        : Colors.blueGrey[50],
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 10,
                                        child: Text(
                                          "  $i",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 25,
                                        child: Text(
                                          date,
                                          style: const TextStyle(fontSize: 12),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 25,
                                        child: Text(
                                          tType,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: typeColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            debitStr,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            creditStr,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 10,
                              child: SizedBox(
                                height: 36,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: (_editingTransaction == t)
                                        ? Colors.grey.withOpacity(0.5)
                                        : (isDark
                                              ? Colors.red[900]!.withOpacity(
                                                  0.4,
                                                )
                                              : Colors.red[100]),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: (_editingTransaction == t)
                                      ? null
                                      : () => _showDeleteTransactionDialog(
                                          party,
                                          t,
                                        ),
                                  child: Icon(
                                    Icons.delete,
                                    color: (_editingTransaction == t)
                                        ? Colors.grey
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: isDark
                            ? Colors.blueGrey[700]
                            : Colors.blueGrey.shade200,
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 8.0,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.blueGrey[700]!
                        : Colors.blueGrey.shade300,
                    width: 2,
                  ),
                ),
                color: isDark ? Colors.blueGrey[800] : Colors.grey[200],
              ),
              child: Row(
                children: [
                  const Expanded(
                    flex: 60,
                    child: Text(
                      "TOTAL",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 15,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        totalDebit.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 15,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        totalCredit.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const Expanded(flex: 10, child: SizedBox()),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 8.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.blueGrey[900] : Colors.grey[300],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: isDark
                              ? Colors.red[900]
                              : Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _generateLedgerPDF(
                          party: party,
                          displayedTransactions: displayedTransactions,
                          isOriginalOpening: isOriginalOpening,
                          displayOpeningVal: displayOpeningVal,
                          displayOpeningType: displayOpeningType,
                          displayOpeningDate: displayOpeningDate,
                          isBeforePartyOpening: isBeforePartyOpening,
                          totalDebit: totalDebit,
                          totalCredit: totalCredit,
                          grandTotal: grandTotal,
                          isDebitBigger: isDebitBigger,
                        ),
                        child: const Text(
                          "PDF",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(
                    flex: 50,
                    child: Text(
                      "GRAND TOTAL",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 30,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        grandTotal.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: grandTotalColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const Expanded(flex: 10, child: SizedBox()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
