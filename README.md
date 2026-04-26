# 🎓 CampusMate — College Student App

A feature-rich Flutter app designed to help college students manage their entire academic life — from tracking attendance and planning study sessions to staying focused with a Pomodoro engine and getting AI-powered study assistance.

---
## ✨ Features

### 🏠 Home Dashboard
A personalized dashboard displaying live stats pulled from all modules:
- Greeting with student name, branch, and time of day
- At-a-glance stats: **Attendance %**, **Tasks Due**, **Notes count**, and **Streak**
- **Productivity card** showing today's focus goal progress and day streak
- Quick access grid to all modules
- Floating **CampusMate AI** button for instant study assistance
- Full dark/light theme support

### 🔐 Login & Registration
- Student sign-up with name, email, branch, and password
- Smooth fade/slide animations on screen transitions
- Student profile data (name, branch, email) passed across all screens

### 🍅 Productivity Engine (Focus / Pomodoro)
A full focus tracking system inspired by habit-building tools:
- **Subjects** — create custom focus subjects (e.g. Deep Work, Reading, Exercise, Coding) each with:
  - Custom emoji icon
  - Focus duration and break duration
  - Sessions per day target
- **Daily Goal** — set a daily focus target (15 min to 5 hours) with quick presets (30 min, 1h, 1.5h, 2h, 3h, 4h)
- **Streak Tracking** — weekly consistency view per subject:
  - 🔥 Full streak — completed 100% of daily goal
  - ⚡ Half streak — completed at least 50%
  - ✗ Missed — less than 50% (streak resets)
- **XP & Levels** — earn XP for completed focus sessions, level up over time
- **Seed/Grove** metaphor — visual growth representation of your focus habit
- **Timer tab** for active Pomodoro sessions

### 📊 Attendance Tracker
- Add subjects with a custom attendance criteria (e.g. 75%)
- Mark lectures as **Attended**, **Missed**, or **Day Off** for each day
- Auto-calculates per subject:
  - Current attendance percentage
  - How many lectures you need to attend to meet your criteria
  - How many lectures you can safely skip
- Data persisted with SharedPreferences

### 📅 Study Planner
- Create and manage daily study tasks with due dates and priorities
- Set reminders via **local push notifications** (scheduled to the minute)
- Persisted with **Hive** (offline-first, no backend needed)
- Timezone-aware scheduling (defaults to `Asia/Kolkata`)

### 🤖 CampusMate AI
An in-app AI study assistant with full context of your academic data:
- Knows your **attendance**, **tasks**, and **notes**
- Answers questions about your college data (e.g. "My attendance 📊")
- Provides study advice, tips, and subject help
- WhatsApp-style chat UI with timestamps
- Accessible from a floating action button on the Home screen

### 📝 Notes
- Organize notes into **folders**
- Attach **images** (from camera or gallery) and **files**
- Filter notes by date
- Stored locally with SharedPreferences

### 📈 Result Predictor
- Enter subject marks and credits
- Configurable grade scale (marks → grade points)
- Calculates **SGPA** and cumulative **CGPA**
- Predicts result based on grade thresholds
- Data persisted with SharedPreferences

### 👤 Profile
- Displays student name, branch, and email
- Dark/light theme toggle (via `ThemeProvider`)
- Logout with navigation back to Login screen

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| State Management | Provider |
| Local Storage | Hive, SharedPreferences |
| Notifications | flutter_local_notifications |
| Timezones | timezone package |
| Image Picking | image_picker |
| File Picking | file_picker |
| AI Assistant | Claude API (Anthropic) |

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `>=3.0.0`
- Dart SDK `>=3.0.0 <4.0.0`
- Android Studio / VS Code with Flutter plugin
- A connected device or emulator

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-username/college-student-app.git
cd college-student-app

# 2. Install dependencies
flutter pub get

# 3. Run code generation (required for Hive models)
dart run build_runner build --delete-conflicting-outputs

# 4. Run the app
flutter run
```

### Building for Release

```bash
# Android APK
flutter build apk --release

# iOS (requires macOS + Xcode)
flutter build ios --release
```

---

## 📁 Project Structure

```
lib/
├── main.dart                        # App entry point, Hive init, theme setup
└── screens/
    ├── home_screen.dart             # Dashboard with live stats & AI button
    ├── login_screen.dart            # Login / Sign-up screen
    ├── attendance_screen.dart       # Attendance tracker
    ├── planner_screen.dart          # Study planner + notifications
    ├── notes_screen.dart            # Notes with folder & file support
    ├── result_screen.dart           # SGPA / CGPA calculator
    ├── pomodoro_screen.dart         # Productivity Engine (Focus/Streaks/XP)
    ├── productivity_engine.dart     # AI assistant chat (CampusMate AI)
    ├── profile_screen.dart          # Student profile & logout
    └── theme_provider.dart          # Dark / light mode state
services/
└── notification_service.dart        # Local notification initialization
```

---

## 🔔 Notifications Setup

The app uses `flutter_local_notifications` for study task reminders.

**Android:** Notification permissions are requested at runtime. A dedicated notification channel (`planner_channel`) is created on first launch.

**iOS:** Alert, badge, and sound permissions are requested via `DarwinInitializationSettings`.

No additional configuration is needed beyond running `flutter pub get`.

---

## 📦 Key Dependencies

```yaml
hive: ^2.2.3                         # Fast, offline key-value store
hive_flutter: ^1.1.0
flutter_local_notifications: ^17.0.0  # Scheduled push notifications
timezone: ^0.9.2                     # Timezone-aware scheduling
provider: ^6.1.5                     # State management
shared_preferences: ^2.5.3           # Lightweight local persistence
image_picker: ^1.0.7                 # Camera / gallery access
file_picker: ^8.0.7                  # Document file access
```

---

## 🙌 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## 📄 License

This project is for educational purposes. Feel free to use and adapt it for your own college projects.
