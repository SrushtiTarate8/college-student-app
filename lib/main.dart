import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/ui/with_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

import 'screens/home_screen.dart';
import 'screens/theme_provider.dart';

import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Timezone
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  // Hive
  await Hive.initFlutter();
  await Hive.openBox<List>('plannerBox');

  // dotenv
  await dotenv.load(fileName: ".env");

  // Notifications
  await initNotifications();

  // Status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(),
          ),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'CampusMate',
              theme: ThemeData(
                primarySwatch: Colors.teal,
                brightness: Brightness.light,
              ),
              darkTheme: ThemeData(
                primarySwatch: Colors.teal,
                brightness: Brightness.dark,
              ),
              themeMode: themeProvider.isDarkMode
                  ? ThemeMode.dark
                  : ThemeMode.light,
              home: const HomeScreen(),
            );
          },
        ),
      ),
    );
  }
}