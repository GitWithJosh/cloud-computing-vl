import streamlit as st
import google.generativeai as genai
from PIL import Image
import io

# Streamlit App-Titel
st.title("Kalorien-Schätzer mit Google Gemini - Version v1.3")
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