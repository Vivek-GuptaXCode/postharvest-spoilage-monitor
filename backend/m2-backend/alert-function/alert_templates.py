"""Bilingual alert message templates (Hindi + English).

Used by the send-alert-notification Cloud Function to format SMS and
Telegram alert messages.  Consistent with M1's Firestore alert schema:
    severity, message, type, acknowledged, warehouse_id
and M4's Flutter display expectations.
"""

TEMPLATES = {
    "critical": {
        "en": (
            "🚨 CRITICAL ALERT — {warehouse}\n"
            "Commodity: {commodity}\n"
            "Risk Score: {risk_score}%\n"
            "Shelf Life: {days_to_spoilage} days\n"
            "Temp: {temperature}°C | Humidity: {humidity}%\n"
            "💰 Est. Loss: ₹{estimated_loss}\n\n"
            "Action: {recommendation}\n"
            "⏰ Act immediately!"
        ),
        "hi": (
            "🚨 गंभीर चेतावनी — {warehouse}\n"
            "फसल: {commodity}\n"
            "जोखिम: {risk_score}%\n"
            "शेल्फ लाइफ: {days_to_spoilage} दिन\n"
            "तापमान: {temperature}°C | नमी: {humidity}%\n"
            "💰 अनुमानित नुकसान: ₹{estimated_loss}\n\n"
            "कार्रवाई: {recommendation}\n"
            "⏰ तुरंत कार्रवाई करें!"
        ),
    },
    "warning": {
        "en": (
            "⚠️ WARNING — {warehouse}\n"
            "Commodity: {commodity} | Risk: {risk_score}%\n"
            "Shelf Life: {days_to_spoilage} days\n"
            "Action: {recommendation}"
        ),
        "hi": (
            "⚠️ चेतावनी — {warehouse}\n"
            "फसल: {commodity} | जोखिम: {risk_score}%\n"
            "शेल्फ लाइफ: {days_to_spoilage} दिन\n"
            "कार्रवाई: {recommendation}"
        ),
    },
}

COMMODITY_NAMES_HI = {
    "tomato": "टमाटर",
    "potato": "आलू",
    "banana": "केला",
    "rice":   "चावल",
    "onion":  "प्याज",
}

RECOMMENDATION_HI = {
    "Activate cold-room ventilation":     "कोल्ड रूम का वेंटिलेशन चालू करें",
    "Increase relative humidity":         "नमी बढ़ाएं — ह्यूमिडिफायर चालू करें",
    "Reduce humidity":                    "नमी कम करें — पंखा या डीह्यूमिडिफायर चालू करें",
    "Ventilate to reduce VOC":            "हवा बदलें — खिड़कियां/दरवाज़े खोलें",
    "Separate ethylene-producing items":  "एथिलीन उत्पादक सामग्री अलग करें",
    "Restore cold storage":               "कोल्ड स्टोरेज का तापमान बहाल करें",
}


def format_alert(
    severity: str,
    language: str,
    warehouse: str = "",
    commodity: str = "",
    risk_score: float = 0,
    days_to_spoilage: float = 0,
    temperature: float = 0,
    humidity: float = 0,
    estimated_loss: float = 0,
    recommendation: str = "",
) -> str:
    """Return a formatted alert string in the requested language.

    Parameters
    ----------
    severity : str
        "critical" or "warning".  Falls back to "warning" template.
    language : str
        "en" or "hi".
    """
    template = TEMPLATES.get(severity, TEMPLATES["warning"]).get(language, "en")

    # Translate commodity name and recommendation for Hindi
    if language == "hi":
        commodity = COMMODITY_NAMES_HI.get(commodity, commodity)
        for en_rec, hi_rec in RECOMMENDATION_HI.items():
            if en_rec.lower() in recommendation.lower():
                recommendation = hi_rec
                break

    return template.format(
        warehouse=warehouse,
        commodity=commodity,
        risk_score=round(risk_score, 1),
        days_to_spoilage=round(days_to_spoilage, 1),
        temperature=round(temperature, 1),
        humidity=round(humidity, 1),
        estimated_loss=round(estimated_loss),
        recommendation=recommendation,
    )
