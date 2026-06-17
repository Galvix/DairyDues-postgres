# 🐄 Galvix DairyDues

> A modern Flutter-based dairy business management application designed
> to simplify daily accounting, payments, loans, and inventory tracking
> for milk vendors and dairy operators.

------------------------------------------------------------------------

## 🚀 Features

✨ **Dashboard Overview** - Daily summaries and financial insights -
Quick navigation across modules

🥛 **Daily Entry Management** - Record milk transactions and
quantities - Automatic balance calculation

👨‍🌾 **Party / Milkman Management** - Manage customers and suppliers -
View transaction history per party

💰 **Payments & Dues** - Record payments easily - Automatic outstanding
balance tracking

🧀 **Paneer Accounting** - Specialized accounting for paneer production
and sales

🏦 **Loan Tracking** - Create, monitor, and settle loans - Payment
history management

☁️ **Cloud Sync** - Firebase Firestore backend with real-time updates

------------------------------------------------------------------------

## 🛠️ Tech Stack

| Layer \| Technology \|

\|-------\|------------\| Frontend \| Flutter (Dart) \| \| Backend \|
Firebase Firestore \| \| Platforms \| Android, Web, Windows \| \|
Architecture \| Service-based Firestore integration \|

------------------------------------------------------------------------

## 📦 Project Structure

    dairy_app/
    │── lib/
    │   ├── main.dart
    │   ├── firebase_options.dart
    │   ├── services/
    │   ├── screens/
    │   └── models/
    │
    │── android/
    │── web/
    │── windows/
    │── firebase.json
    │── firestore.indexes.json

------------------------------------------------------------------------

## ⚙️ Getting Started

### 1️⃣ Clone Repository

``` bash
git clone https://github.com/yourusername/GalvixDairyDues.git
cd GalvixDairyDues/dairy_app
```

### 2️⃣ Install Dependencies

``` bash
flutter pub get
```

### 3️⃣ Firebase Setup 🔥

Install FlutterFire CLI:

``` bash
dart pub global activate flutterfire_cli
```

Configure Firebase:

``` bash
flutterfire configure
```

Ensure the generated file exists:

    lib/firebase_options.dart

### 4️⃣ Run the App

``` bash
flutter run
```

For specific platforms:

``` bash
flutter run -d chrome
flutter run -d windows
```

------------------------------------------------------------------------

## 📱 Core Workflows

### Daily Operations

1.  Add milk delivery entries
2.  Record payments
3.  Track balances automatically
4.  View dashboard insights

### Financial Management

-   Loan creation and settlement
-   Paneer production accounting
-   Party-wise ledger tracking

------------------------------------------------------------------------

## 🔐 Firestore Notes

The app relies on compound indexes defined in:

    firestore.indexes.json

If queries fail, deploy indexes using:

``` bash
firebase deploy --only firestore:indexes
```

------------------------------------------------------------------------

## 🤝 Contributing

Contributions are welcome!

1.  Fork the repository
2.  Create a feature branch
3.  Commit changes
4.  Open a Pull Request

------------------------------------------------------------------------

## 👨‍💻 Author

**Galvix**

------------------------------------------------------------------------

⭐ If you like this project, consider giving it a star!
