import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_storage/shared_storage.dart' as saf;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
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

void main() async {
  // Ensures all Flutter components are completely bound and ready before modifying platform UI settings
  WidgetsFlutterBinding.ensureInitialized();

  // Immersive Sticky mode hides both the top status bar and bottom navigation bar completely
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialize Firebase
  await Firebase.initializeApp();

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
          elevation: 8,
        ),
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
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
String currentLayoutSetting = "SBL";
String globalShopName = "RETAIL INVOICE";
String currentThemeSetting = "DARK";
User? currentFirebaseUser;

// --- LOCAL STORAGE HELPER LOGIC ---
class LocalDatabase {
  static Future<Uri?> getBaseFolderUri() async {
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
    final baseUri = await getBaseFolderUri();
    if (baseUri == null) return null;
    var folder = await saf.child(baseUri, "INTERNAL_SETTINGS");
    if (folder == null) {
      var doc = await saf.createDirectory(baseUri, "INTERNAL_SETTINGS");
      return doc?.uri;
    }
    return folder.uri;
  }

  static Future<void> saveToDisk() async {
    try {
      final settingsUri = await getSettingsFolderUri();
      if (settingsUri == null) return;
      var file = await saf.child(settingsUri, 'inventory_db.json');
      final content = jsonEncode(globalInventory);
      final bytes = Uint8List.fromList(utf8.encode(content));
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
      final settingsUri = await getSettingsFolderUri();
      if (settingsUri == null) return;
      var file = await saf.child(settingsUri, 'inventory_db.json');
      if (file != null) {
        final bytes = await saf.getDocumentContent(file.uri);
        if (bytes != null) {
          final content = utf8.decode(bytes);
          Map<String, dynamic> decoded = jsonDecode(content);
          Map<String, List<Map<String, String>>> loadedInventory = {};
          decoded.forEach((key, value) {
            loadedInventory[key] = (value as List)
                .map((item) => Map<String, String>.from(item))
                .toList();
          });
          globalInventory = loadedInventory;
        }
      }
    } catch (e) {
      debugPrint("Error auto-loading database: $e");
    }
  }

  static Future<void> saveAppSettings() async {
    try {
      final settingsUri = await getSettingsFolderUri();
      if (settingsUri == null) return;
      var file = await saf.child(settingsUri, 'app_settings.json');
      final content = jsonEncode({
        "layout": currentLayoutSetting,
        "shopName": globalShopName,
        "theme": currentThemeSetting,
      });
      final bytes = Uint8List.fromList(utf8.encode(content));
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
      final settingsUri = await getSettingsFolderUri();
      if (settingsUri == null) return;
      var file = await saf.child(settingsUri, 'app_settings.json');
      if (file != null) {
        final bytes = await saf.getDocumentContent(file.uri);
        if (bytes != null) {
          final content = utf8.decode(bytes);
          Map<String, dynamic> decoded = jsonDecode(content);
          currentLayoutSetting = decoded["layout"] ?? "SBL";
          globalShopName = decoded["shopName"] ?? "RETAIL INVOICE";
          currentThemeSetting = decoded["theme"] ?? "DARK";
        }
      }
    } catch (e) {
      debugPrint("Error loading app configuration: $e");
    }
  }

  static Future<Uri?> getBackupsFolderUri() async {
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
    final baseUri = await getBaseFolderUri();
    if (baseUri == null) return null;
    var folder = await saf.child(baseUri, "MYBILLS");
    if (folder == null) {
      var doc = await saf.createDirectory(baseUri, "MYBILLS");
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
            'inventory': inventoryData,
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
          // Also save to local disk so offline works
          await LocalDatabase.saveToDisk();
        }
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
        currentLayoutSetting = data['layout'] ?? "SBL";
        globalShopName = data['shopName'] ?? "RETAIL INVOICE";
        currentThemeSetting = data['theme'] ?? "DARK";
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

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndInit();
  }

  Future<void> _checkPermissionsAndInit() async {
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

    await LocalDatabase.loadFromDisk();
    await LocalDatabase.loadAppSettings();

    // Check if user was previously signed in
    currentFirebaseUser = FirebaseAuth.instance.currentUser;

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
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
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
            ],
          );
        },
      ),
    );

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
      builder: (context) => Dialog(
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
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
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
                            "SHOW RATE",
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
                                Theme.of(context).brightness == Brightness.dark
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

            return Container(
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
                            padding: const EdgeInsets.symmetric(horizontal: 4),
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
                                  : (v) => setPopupState(() => currentUnit = u),
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
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        double q = double.tryParse(localQty) ?? 0;
                        double r = double.tryParse(localRate) ?? 0;

                        double total = 0.0;
                        if (masterUnit == currentUnit) {
                          total = q * r;
                        } else if (masterUnit == "Kg" &&
                            currentUnit == "GRAM") {
                          total = (q / 1000.0) * r;
                        } else if (masterUnit == "GRAM" &&
                            currentUnit == "Kg") {
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
                      },
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
            );
          },
        ),
      ),
    );
  }

  void _showCart() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setCartState) {
          double cartTotal = _cart.fold(0, (sum, item) => sum + item['total']);
          return Dialog(
            child: Container(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "CURRENT BILL",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        flex: 8,
                                        child: InkWell(
                                          onTap: () {
                                            Map<String, String>? baseItemMatch;
                                            globalInventory.forEach((
                                              cat,
                                              items,
                                            ) {
                                              for (var item in items) {
                                                String baseName =
                                                    item['name'] ?? "";
                                                String regName =
                                                    item['regional_name'] ?? "";
                                                String testName =
                                                    regName.isNotEmpty
                                                    ? "$baseName ($regName)"
                                                    : baseName;
                                                if (testName ==
                                                        cartItem['name'] ||
                                                    baseName ==
                                                        cartItem['name'])
                                                  baseItemMatch = item;
                                              }
                                            });

                                            baseItemMatch ??= {
                                              'name': cartItem['name'],
                                              'rate': cartItem['rate'],
                                              'unit': cartItem['unit'],
                                            };
                                            Navigator.pop(context);
                                            _showItemEntryPopup(
                                              baseItemMatch!,
                                              editCartIndex: index,
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? Colors.blueGrey[800]
                                                  : Colors.blueGrey[50],
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
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
                                                ? Colors.red[900]!.withOpacity(
                                                    0.4,
                                                  )
                                                : Colors.red[100],

                                            elevation: 0,
                                          ),
                                          onPressed: () async {
                                            bool confirm =
                                                await _showConfirmationWarning(
                                                  context,
                                                  "DO YOU REALLY WANT TO\nREMOVE THIS ITEM?",
                                                );
                                            if (confirm) {
                                              setState(
                                                () => _cart.removeAt(index),
                                              );
                                              setCartState(() {});
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
                                : () => _showCustomerNamePopup(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.blueGrey[700]
                                  : Colors.blueGrey[900],
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              "GENERATE BILL (₹${cartTotal.toStringAsFixed(2)})",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                                    bool
                                    confirm = await _showConfirmationWarning(
                                      context,
                                      "DO YOU REALLY WANT TO\nCLEAR THE ENTIRE CART?",
                                    );
                                    if (confirm) {
                                      setState(() => _cart = []);
                                      if (context.mounted)
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
            ),
          );
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
                    return ListTile(
                      title: Text(
                        finalTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "₹${_searchResults[index]['rate']} per ${_searchResults[index]['unit']}",
                      ),
                      onTap: () => _showItemEntryPopup(_searchResults[index]),
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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.3,
        ),
        itemBuilder: (context, index) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.blueGrey[800]
                  : Colors.blueGrey[50],
              foregroundColor: isDark ? Colors.white : Colors.blueGrey[900],
              elevation: 1,

              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: () =>
                setState(() => _selectedCategoryForGrid = categories[index]),
            child: Text(
              categories[index].toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
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
                          backgroundColor: isDark
                              ? Colors.orange[900]!.withOpacity(0.3)
                              : Colors.orange[50],
                          foregroundColor: isDark
                              ? Colors.orange[100]
                              : Colors.blueGrey[900],

                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: () => _showItemEntryPopup(item),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
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
                                color: isDark
                                    ? Colors.orange[200]
                                    : Colors.blueGrey[600],
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

  @override
  Widget build(BuildContext context) {
    double totalBill = _cart.fold(0, (sum, item) => sum + item['total']);
    return Scaffold(
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
              MaterialPageRoute(builder: (context) => const WarehouseScreen()),
            ).then((_) => setState(() {})),
          ),
        ],
      ),
      body: _isLoadingDb
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildMiddleLayout()),
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
  Future<File?> _executeSilentInventoryExport() async {
    try {
      final backupUri = await LocalDatabase.getBackupsFolderUri();
      if (backupUri == null) return null;
      var file = await saf.child(backupUri, 'inventory_data.json');
      final content = jsonEncode(globalInventory);
      final bytes = Uint8List.fromList(utf8.encode(content));
      if (file == null) {
        await saf.createFileAsBytes(
          backupUri,
          mimeType: 'application/json',
          displayName: 'inventory_data.json',
          bytes: bytes,
        );
      } else {
        await saf.writeToFileAsBytes(file.uri, bytes: bytes);
      }

      // Create a cache copy for sharing
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/inventory_data.json');
      await tempFile.writeAsBytes(bytes);
      return tempFile;
    } catch (e) {
      debugPrint("Silent export handling issue: $e");
    }
    return null;
  }

  // Triggered via the 20% Export Share button
  Future<void> _exportAndShareInventoryFile() async {
    final File? file = await _executeSilentInventoryExport();
    if (file != null && await file.exists()) {
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'My Billing App Inventory Backup');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to compile or share local backup string."),
          ),
        );
      }
    }
  }

  // Triggered via the 20% Import button (Reads from the static local path completely offline)
  Future<void> _importLocalBackupDirectlyFromFolder() async {
    try {
      final backupUri = await LocalDatabase.getBackupsFolderUri();
      if (backupUri == null) return;
      var file = await saf.child(backupUri, 'inventory_data.json');
      if (file != null) {
        final bytes = await saf.getDocumentContent(file.uri);
        if (bytes != null) {
          final content = utf8.decode(bytes);
          Map<String, dynamic> decoded = jsonDecode(content);
          Map<String, List<Map<String, String>>> verifiedInventory = {};

          decoded.forEach((key, value) {
            verifiedInventory[key] = (value as List)
                .map((item) => Map<String, String>.from(item))
                .toList();
          });

          setState(() {
            globalInventory = verifiedInventory;
          });
          await LocalDatabase.saveToDisk();
          await LocalDatabase.saveAppSettings();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Inventory successfully imported locally!"),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No 'inventory_data.json' backup found in folder."),
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

  void _showCenterBackupMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            // --- ROW 1: EXPORT SYSTEM (80% / 20%) ---
            Row(
              children: [
                Expanded(
                  flex: 8,
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (currentFirebaseUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please sign in first!"),
                            ),
                          );
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);

                        if (!await CloudDatabase.hasInternetConnection()) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text("Failed: No internet connection!"),
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
                        await CloudDatabase.syncInventoryToCloud();
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
                      onPressed: () {
                        Navigator.pop(context);
                        _exportAndShareInventoryFile();
                      },
                      style: ElevatedButton.styleFrom(
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
            // --- ROW 2: IMPORT SYSTEM (80% / 20%) ---
            Row(
              children: [
                Expanded(
                  flex: 8,
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (currentFirebaseUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please sign in first!"),
                            ),
                          );
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);

                        if (!await CloudDatabase.hasInternetConnection()) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text("Failed: No internet connection!"),
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
                        await CloudDatabase.loadInventoryFromCloud();
                        await CloudDatabase.loadSettingsFromCloud();
                        smartBillingAppKey.currentState?.rebuildApp();
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
                      onPressed: () {
                        Navigator.pop(context);
                        _importLocalBackupDirectlyFromFolder();
                      },
                      style: ElevatedButton.styleFrom(
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
          ],
        ),
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
                      "SHOP NAME",
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
                          onTap: () => setPopupState(() => tempLayout = "SBL"),
                        ),
                        const SizedBox(height: 8),
                        _buildLayoutOption(
                          title: "DIRECT GRID LAYOUT",
                          icon: Icons.grid_view,
                          layoutCode: "DGL",
                          currentSelection: tempLayout,
                          onTap: () => setPopupState(() => tempLayout = "DGL"),
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
                  MaterialPageRoute(
                    builder: (context) => const HistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text("HISTORY"),
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
  List<saf.DocumentFile> _allPdfFiles = [];
  List<saf.DocumentFile> _filteredPdfFiles = [];
  final TextEditingController _historySearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
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
        String printableName = _parseInvoiceNameForDisplay(
          file.name ?? "",
        ).toLowerCase();
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
                                          final bytes = await saf
                                              .getDocumentContent(file.uri);
                                          if (bytes != null) {
                                            final tempFile = File(
                                              '${Directory.systemTemp.path}/${file.name}',
                                            );
                                            await tempFile.writeAsBytes(bytes);
                                            OpenFilex.open(tempFile.path);
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
                                                  file.name ?? "Unknown",
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
                                          final bytes = await saf
                                              .getDocumentContent(file.uri);
                                          if (bytes != null) {
                                            final tempFile = File(
                                              '${Directory.systemTemp.path}/${file.name}',
                                            );
                                            await tempFile.writeAsBytes(bytes);
                                            Share.shareXFiles([
                                              XFile(tempFile.path),
                                            ], text: 'Invoice Sharing');
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

  Future<bool> _showWarning(String msg) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
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
                    onPressed: () async {
                      if (_catC.text.isNotEmpty) {
                        globalInventory[_catC.text] = [];
                        await LocalDatabase.saveToDisk();
                        setState(() {});
                      }
                      _catC.clear();
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
                          child: Icon(Icons.menu, color: Colors.blueGrey),
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
                        flex: 8,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            alignment: Alignment.centerLeft,
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
                          child: const Icon(
                            Icons.delete,
                            color: Colors.red,
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

  bool get _isValid =>
      _englishNameController.text.trim().isNotEmpty &&
      _r.text.trim().isNotEmpty &&
      _selectedUnit != null;

  Future<bool> _showWarning(String msg) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
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
            SizedBox(
              width: double.infinity,
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
                          'regional_name': _regionalNameController.text.trim(),
                          'rate': _r.text.trim(),
                          'unit': _selectedUnit!,
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
                        setState(() {});
                      },
                child: Text(
                  _editingIndex == null ? "ADD ITEM" : "SAVE CHANGES",
                  style: TextStyle(
                    color: _isValid ? Colors.white : Colors.grey[600],
                  ),
                ),
              ),
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
                            child: Icon(Icons.menu, color: Colors.blueGrey),
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
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isEditing
                                    ? (isDark
                                          ? Colors.orange[900]!.withOpacity(0.3)
                                          : Colors.orange[50])
                                    : (isDark
                                          ? Colors.blueGrey[800]
                                          : Colors.blueGrey[50]),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
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
                                      color: isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
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
                                        ? Colors.red[900]!.withOpacity(0.4)
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
