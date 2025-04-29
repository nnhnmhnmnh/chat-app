# AI Chat App (Flutter)

A modern AI-powered chat application built with Flutter. Integrates Google Gemini API, Firebase, Supabase, and Google Sign-In. Supports rich media input, customizable chat experience, and advanced features like YouTube content analysis and Google Form automation.

---

## Features

- Chat with AI using [Google Gemini](https://deepmind.google/technologies/gemini/)
- Text-to-Image generation from user prompts
- Upload images, videos, audio, PDFs, and other files
- Analyze and generate content from YouTube video links
- Auto-fill Google Forms via `@AutoFillGForm` command
- Search through chat history
- Customize chatbot name, avatar, and system instructions
- Light / Dark / System theme switch
- Multilingual support: English & Vietnamese
- Secure login with Google
- Cloud storage via Firebase Firestore & Supabase Storage

---

## Tech Stack

- **Flutter** + **Dart**
- **Firebase** Auth & Firestore
- **Supabase** Storage
- **Google Gemini API**
- **Google Sign-In**
- SharedPreferences, Provider, Markdown rendering
- Audio & Video handling, File Picker, Image Picker

---

## Demo

https://github.com/user-attachments/assets/30bfe337-3bdf-4ecd-9003-a81b80ed5060

---

## Getting Started

### 1. Clone the project

```bash
git clone https://github.com/nnhnmhnmnh/chat-app.git
cd chat-app
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Configure environment

Create a .env file in the root directory:

```env
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
API_KEY=your_google_gemini_api_key
```

### 4. Setup Firebase & Supabase

- Connect Firebase using flutterfire CLI
- In Supabase, create a bucket named ai-chat-bucket

### 5. Run the app

```bash
flutter run
```

## Authentication

Google Sign-In is used for user authentication. User data is securely stored in Firestore and files in Supabase. Users can sign out or delete all chat history.