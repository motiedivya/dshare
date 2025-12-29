# DShare: A Django-Based File Sharing Platform

DShare is a Django-based web application that allows users to share files and text between devices using special keywords. It supports a truly public (guest) mode and optional accounts with one-time email verification + passkeys (preferred) or PIN/password fallback.

## Features

- Public (guest) sharing mode
- Optional accounts with email verification
- Passkeys (WebAuthn) preferred, with optional PIN/password fallback
- File upload and download using special keywords
- Clipboard text pasting support
- Dark theme using Tailwind CSS
- Easy deployment to PythonAnywhere

## Technologies Used

- Django
- Python
- Tailwind CSS
- JavaScript

## Setup Instructions

### Prerequisites

- Python 3.10 or later
- Virtual environment (recommended)
- Git

### Local Setup

1. **Clone the repository**:

   ```bash
   git clone https://github.com/motiedivya/dshare.git
   cd dshare
   ```
2. **Create and activate a virtual environment**:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```
3. **Install dependencies**:

   ```bash
   pip install -r requirements.txt
   ```
4. **Configure the database**:

   ```bash
   python manage.py migrate
   ```
5. **Run the development server**:

   ```bash
   python manage.py runserver
   ```
6. **Access the application**:

   Open a web browser and go to `http://127.0.0.1:8000`.

### Email (SMTP)

1. **Configure Django to use SMTP** (example env vars):

   ```bash
   export DJANGO_EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
   export EMAIL_HOST=smtp.gmail.com
   export EMAIL_PORT=587
   export EMAIL_USE_TLS=1
   export EMAIL_HOST_USER=gmailuser
   export EMAIL_HOST_PASSWORD="YOUR_SMTP_GMAIL_KEY"
   export DEFAULT_FROM_EMAIL="do-not-reply-gmailuser@gmail.com"
   ```

   Notes:

   - For implicit SSL, use `EMAIL_PORT=465` and `EMAIL_USE_SSL=1` (and set `EMAIL_USE_TLS=0`).
   - In development you can keep the default console backend (emails print to the server console).

### Deployment to PythonAnywhere

1. **Sign up or log in to PythonAnywhere**:

   Go to [PythonAnywhere](https://www.pythonanywhere.com/) and create an account or log in.
2. **Create a new web app**:

   - Go to the "Web" tab and click "Add a new web app".
   - Choose "Manual configuration" and select "Python 3.10".
3. **Set up the project**:

   - Open a Bash console on PythonAnywhere.
   - Clone your repository:

     ```bash
     git clone https://github.com/yourusername/dshare.git
     cd dshare
     ```
   - Create and activate a virtual environment:

     ```bash
     python3 -m venv .venv
     source .venv/bin/activate
     pip install -r requirements.txt
     ```
4. **Configure WSGI**:

   - Go to the "Web" tab and click on "WSGI configuration file".
   - Update the file to point to your Django project:

     ```python
     import os
     import sys

     # Add your project directory to the sys.path
     project_home = os.path.expanduser('~/dshare')
     if project_home not in sys.path:
         sys.path = [project_home] + sys.path

     # Point to your project's settings module
     os.environ['DJANGO_SETTINGS_MODULE'] = 'dshare.settings'

     # Activate your virtual environment
     activate_this = os.path.expanduser('~/dshare/.venv/bin/activate_this.py')
     with open(activate_this) as f:
         exec(f.read(), dict(__file__=activate_this))

     # Import the Django WSGI application
     from django.core.wsgi import get_wsgi_application
     application = get_wsgi_application()
     ```
5. **Set up static files and media files**:

   - In the "Web" tab, configure static files:
     - URL: `/static/` and Path: `/home/yourusername/dshare/static`
     - URL: `/media/` and Path: `/home/yourusername/dshare/media`
6. **Set environment variables**:

   - In the "Web" tab under "Configuration", set the `DJANGO_SETTINGS_MODULE` environment variable to `dshare.settings`.
7. **Run migrations and collect static files**:

   - Open a Bash console on PythonAnywhere:

     ```bash
     cd ~/dshare
     source .venv/bin/activate
     python manage.py migrate
     python manage.py collectstatic
     ```
8. **Reload the web app**:

   - Go to the "Web" tab and click on "Reload".

### Usage

The home screen is intentionally minimal: just type keywords/commands.

1. **Public (guest) mode**:

   - Just open the site and type `divya` to upload or paste text (public).
   - Type `moti` to download/view the latest public upload/text.
2. **Register / verify email (one-time)**:

   - Type `/register` and enter your email (and an optional PIN/password fallback).
   - Click the verification link sent to your email; this verifies your email and logs you in.
   - If your browser supports passkeys, you’ll be prompted once to create a passkey (recommended).
3. **Login (when session expires / new device)**:

   - Type `/login` (tries passkey first; falls back to email + PIN/password).
4. **Private mode (logged in)**:

   - Type `divya` / `moti` exactly like before, but it now uses your private storage.
5. **Clipboard commands**:

   - `/paste` uploads clipboard text
   - `/copy` copies the latest stored text to clipboard
   - `/clear` clears stored file/text (and attempts to clear clipboard)

### Contributing

We welcome contributions to improve this project! Please follow these steps to contribute:

1. Fork the repository.
2. Create a new branch (`git checkout -b feature/your-feature`).
3. Make your changes and commit them (`git commit -m 'Add your feature'`).
4. Push to the branch (`git push origin feature/your-feature`).
5. Open a pull request.

### License

This project is licensed under the MIT License.

### Contact

For any questions or feedback, please contact Divyesh Vishwakarma at divyesh.v@neuralit.com.
