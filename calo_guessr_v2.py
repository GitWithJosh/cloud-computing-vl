import streamlit as st
import google.generativeai as genai
from PIL import Image
import io
import os

# Session State initialisieren für Chat-Verlauf und Analyse-Ergebnis
if 'chat_history' not in st.session_state:
    st.session_state.chat_history = []
if 'calorie_analysis' not in st.session_state:
    st.session_state.calorie_analysis = None
if 'api_key_set' not in st.session_state:
    st.session_state.api_key_set = False

# Streamlit App-Titel
st.title("Kalorien-Schätzer mit Chat-Funktion")
st.write("Lade ein Bild deines Essens hoch, erhalte eine Kalorienanalyse und chatte darüber mit Gemini.")

# Sidebar mit Erklärungen
with st.sidebar:
    st.header("Anleitung")
    st.write("""
    1. Gib deinen Google Gemini API-Schlüssel ein
    2. Lade ein Bild deines Essens hoch
    3. Erhalte eine Kalorienanalyse
    4. Stelle Fragen zur Analyse oder erhalte Ernährungstipps
    """)
    
    st.header("Info")
    st.write("""
    Diese App verwendet die Google Gemini API für:
    - Kalorienanalyse aus Bildern
    - Chat-Funktion mit Kontext der letzten 3 Nachrichten
    """)

# API-Schlüssel eingeben
api_key = st.text_input("Google Gemini API-Schlüssel", type="password")
if api_key:
    # API-Schlüssel konfigurieren
    genai.configure(api_key=api_key)
    st.session_state.api_key_set = True

# Funktion zum Kalorien-Schätzen
def estimate_calories(image, api_key):
    try:
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

# Funktion für Gemini Chat mit Kontextfenster
def chat_with_gemini(user_input, chat_history, calorie_analysis):
    try:
        # Modell auswählen
        model = genai.GenerativeModel('gemini-2.0-flash')
        
        # Kontextfenster erstellen (letzte 3 Nachrichten + Kalorienanalyse)
        context = f"Du bist ein Ernährungsberater, der auf Basis einer Kalorienanalyse hilft. "
        context += f"Die letzte Kalorienanalyse war: {calorie_analysis}\n\n"
        
        # Die letzten 3 Nachrichten aus dem Chat-Verlauf einfügen (falls vorhanden)
        recent_messages = chat_history[-3:] if len(chat_history) > 0 else []
        for msg in recent_messages:
            if msg['role'] == 'user':
                context += f"Nutzer: {msg['content']}\n"
            else:
                context += f"Assistent: {msg['content']}\n"
        
        prompt = context + f"\nNutzer: {user_input}\nAntworte in deutscher Sprache."
        
        # Chat-Anfrage senden
        response = model.generate_content(prompt)
        
        return response.text
    
    except Exception as e:
        return f"Fehler beim Chat: {str(e)}"

# Tab-Layout
tab1, tab2 = st.tabs(["Kalorienanalyse", "Chat"])

# Tab 1: Bild hochladen und Kalorien analysieren
with tab1:
    st.header("Kalorienanalyse")
    
    # Bild-Upload
    uploaded_file = st.file_uploader("Lade ein Bild deines Essens hoch", type=["jpg", "jpeg", "png"])
    
    # Bild anzeigen und Kalorien schätzen
    if uploaded_file is not None:
        image = Image.open(uploaded_file)
        
        # Bild anzeigen
        st.image(image, caption="Hochgeladenes Bild", use_column_width=True)
        
        # Button zum Schätzen der Kalorien
        if st.button("Kalorien schätzen"):
            if st.session_state.api_key_set:
                with st.spinner("Analyse läuft... (Dies kann einige Sekunden dauern)"):
                    result = estimate_calories(image, api_key)
                    st.session_state.calorie_analysis = result
                    st.subheader("Ergebnis der Kalorienanalyse")
                    st.write(result)
                    st.success("Analyse abgeschlossen! Wechsle zum Chat-Tab, um Fragen zu stellen.")
            else:
                st.error("Bitte gib einen Google Gemini API-Schlüssel ein.")

# Tab 2: Chat mit Gemini
with tab2:
    st.header("Chat mit Gemini")
    
    # Prüfen, ob bereits eine Kalorienanalyse vorliegt
    if st.session_state.calorie_analysis is None:
        st.info("Bitte führe zuerst eine Kalorienanalyse im ersten Tab durch.")
    else:
        # Zeige die letzte Analyse als Zusammenfassung an
        with st.expander("Letzte Kalorienanalyse (Klicken zum Anzeigen)"):
            st.write(st.session_state.calorie_analysis)
        
        # Chat-Verlauf anzeigen
        st.subheader("Chat-Verlauf")
        for message in st.session_state.chat_history:
            with st.chat_message(message["role"]):
                st.write(message["content"])
        
        # Chat-Eingabe
        user_input = st.chat_input("Stelle eine Frage zur Kalorienanalyse...")
        
        # Wenn Benutzer eine Frage stellt
        if user_input:
            # Benutzer-Nachricht anzeigen
            with st.chat_message("user"):
                st.write(user_input)
            
            # Nachricht zum Verlauf hinzufügen
            st.session_state.chat_history.append({"role": "user", "content": user_input})
            
            # Gemini-Antwort generieren
            if st.session_state.api_key_set:
                with st.spinner("Gemini denkt nach..."):
                    response = chat_with_gemini(user_input, st.session_state.chat_history, st.session_state.calorie_analysis)
                    
                    # Antwort anzeigen
                    with st.chat_message("assistant"):
                        st.write(response)
                    
                    # Antwort zum Verlauf hinzufügen
                    st.session_state.chat_history.append({"role": "assistant", "content": response})
            else:
                st.error("Bitte gib einen Google Gemini API-Schlüssel ein.")

# Fußzeile
st.markdown("---")
st.markdown("Entwickelt mit Streamlit und Google Gemini API")