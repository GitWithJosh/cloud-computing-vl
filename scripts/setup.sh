#!/bin/bash
set -e

# Log setup process
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting setup script for Python application deployment..."

# Update system packages
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y python3 python3-pip python3-venv nginx

# Create application directory
echo "Creating application directory..."
APP_DIR="/opt/python-app"
mkdir -p $APP_DIR

# Copy application files
echo "Setting up application files for version ${app_version}..."
cat > $APP_DIR/app.py << 'EOL'
#!/usr/bin/env python3
"""
Simple web application using Streamlit
"""

import streamlit as st
import google.generativeai as genai
from PIL import Image
import io
import os

# Streamlit App-Titel
st.title("Kalorien-Schätzer mit Google Gemini")
st.write("Lade ein Bild deines Essens hoch und die KI wird die Kalorien schätzen.")

# Sidebar mit Erklärungen
with st.sidebar:
    st.header("Anleitung")
    st.write("""
    1. Gib deinen Google Gemini API-Schlüssel ein
    2. Lade ein Bild deines Essens hoch
    3. Klicke auf 'Kalorien schätzen'
    4. Erhalte eine Schätzung der Kalorien und Nährwerte
    """)
    
    st.header("Info")
    st.write("""
    Diese App verwendet die Google Gemini API, um Kalorien in Lebensmitteln zu schätzen. 
    Die Genauigkeit hängt von der Bildqualität und der API-Fähigkeit ab.
    """)

# API-Schlüssel eingeben
api_key = st.text_input("Google Gemini API-Schlüssel", type="password")

# Funktion zum Kalorien-Schätzen
def estimate_calories(image, api_key):
    try:
        # Konfiguriere die API mit dem Schlüssel
        genai.configure(api_key=api_key)
        
        # Modell auswählen und initialisieren
        model = genai.GenerativeModel('gemini-2.0-flash')
        
        # Prompt für die Kalorienberechnung
        prompt = """
        Analysiere dieses Bild von Lebensmitteln und gib eine detaillierte Schätzung der enthaltenen Kalorien ab.
        
        Bitte gib folgende Informationen an:
        1. Identifiziere die Lebensmittel im Bild
        2. Schätze die Gesamtkalorien
        3. Schätze die Makronährstoffe (Proteine, Kohlenhydrate, Fette)
        4. Gib eine Genauigkeitseinschätzung deiner Analyse
        
        Antworte in deutscher Sprache.
        """
        
        # Bild in ein byte-format konvertieren
        img_byte_arr = io.BytesIO()
        image.save(img_byte_arr, format='JPEG')
        img_byte_arr = img_byte_arr.getvalue()
        
        # API-Anfrage senden
        response = model.generate_content([prompt, {"mime_type": "image/jpeg", "data": img_byte_arr}])
        
        return response.text
    
    except Exception as e:
        return f"Fehler bei der API-Anfrage: {str(e)}"

# Bild-Upload
uploaded_file = st.file_uploader("Lade ein Bild deines Essens hoch", type=["jpg", "jpeg", "png"])

# Bild anzeigen und Kalorien schätzen
if uploaded_file is not None:
    image = Image.open(uploaded_file)
    
    # Bild anzeigen
    st.image(image, caption="Hochgeladenes Bild", use_column_width=True)
    
    # Button zum Schätzen der Kalorien
    if st.button("Kalorien schätzen"):
        if api_key:
            with st.spinner("Analyse läuft... (Dies kann einige Sekunden dauern)"):
                result = estimate_calories(image, api_key)
                st.subheader("Ergebnis der Kalorienanalyse")
                st.write(result)
        else:
            st.error("Bitte gib einen Google Gemini API-Schlüssel ein.")

# Fußzeile
st.markdown("---")
st.markdown("Entwickelt mit Streamlit und Google Gemini API")
EOL

# Create requirements.txt
cat > $APP_DIR/requirements.txt << 'EOL'
streamlit==1.31.0
Pillow==10.2.0
google-generativeai==0.3.2
python-dotenv==1.0.1
flask==2.3.3
gunicorn==21.2.0
EOL

# Set up Python virtual environment
echo "Setting up Python virtual environment..."
cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Create a systemd service file to run the application
echo "Creating systemd service..."
cat > /etc/systemd/system/python-app.service << EOL
[Unit]
Description=Streamlit App Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/streamlit run app.py --server.port=8080 --server.address=0.0.0.0
Restart=on-failure
Environment="APP_VERSION=${app_version}"

[Install]
WantedBy=multi-user.target
EOL


# Set up Nginx as a reverse proxy
echo "Setting up Nginx reverse proxy..."
cat > /etc/nginx/sites-available/python-app << 'EOL'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOL

# Enable the Nginx site
ln -sf /etc/nginx/sites-available/python-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# Enable and start the service
echo "Enabling and starting the Python service..."
systemctl daemon-reload
systemctl enable python-app.service
systemctl start python-app.service

# Add version info to a visible file
echo "Version: ${app_version}" > /opt/python-app/VERSION

echo "Setup completed successfully!"