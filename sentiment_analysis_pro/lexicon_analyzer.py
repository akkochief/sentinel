"""
lexicon_analyzer.py
====================
Sözlük tabanlı (rule-based) sentiment analiz motoru.
Herhangi bir eğitim verisine ihtiyaç duymadan, anında çalışır.
Negasyon (olumsuzlama) penceresi, güçlendirici/zayıflatıcı kelimeler
ve emoji desteği içerir.
"""

import re
from dataclasses import dataclass, field


POSITIVE_WORDS = {
    "harika", "mükemmel", "güzel", "iyi", "mutlu", "sevindim", "başarılı",
    "muhteşem", "keyifli", "memnun", "beğendim", "süper", "teşekkür",
    "kaliteli", "hızlı", "tavsiye", "sevdim", "sevgi", "olağanüstü",
    "efsane", "bayıldım", "şahane", "temiz", "rahat", "keyif", "gurur",
    "umut", "pozitif", "nefis", "lezzetli", "konforlu", "şık", "ferah",
    "good", "great", "excellent", "amazing", "awesome", "happy", "love",
    "wonderful", "fantastic", "nice", "best", "perfect", "positive",
    "recommend", "beautiful", "enjoyed", "satisfied", "delight", "brilliant",
}

NEGATIVE_WORDS = {
    "kötü", "berbat", "korkunç", "üzgün", "üzücü", "başarısız", "yavaş",
    "pahalı", "rezalet", "beğenmedim", "sevmedim", "nefret", "kızgın",
    "sinir", "bozuk", "kırık", "yetersiz", "vasat", "iğrenç", "problem",
    "sorun", "şikayet", "pişman", "negatif", "kirli", "gecikme", "sıkıntı",
    "bezgin", "rahatsız", "kalitesiz", "hayalkırıklığı", "felaket",
    "bad", "terrible", "awful", "horrible", "sad", "hate", "worst",
    "poor", "disappointing", "disappointed", "negative", "problem",
    "broken", "slow", "expensive", "angry", "annoying", "disgusting",
}

NEGATORS = {"değil", "yok", "hiç", "not", "no", "never", "asla", "olmadı"}

INTENSIFIERS = {
    "çok": 1.6, "aşırı": 1.8, "gerçekten": 1.4, "son": 1.3, "derece": 1.3,
    "inanılmaz": 1.7, "oldukça": 1.3,
    "very": 1.6, "really": 1.4, "extremely": 1.8, "so": 1.3, "totally": 1.5,
}

DIMINISHERS = {
    "biraz": 0.6, "az": 0.5, "kısmen": 0.6,
    "slightly": 0.6, "somewhat": 0.6, "a": 1.0,
}

POSITIVE_EMOJIS = {"😀", "😃", "😄", "😁", "😊", "🙂", "❤️", "👍", "🎉", "😍"}
NEGATIVE_EMOJIS = {"😞", "😢", "😡", "👎", "💔", "😠", "😭", "🤬"}

# Negasyonun etkili olduğu maksimum kelime mesafesi (pencere boyutu)
NEGATION_WINDOW = 3


@dataclass
class SentimentResult:
    text: str
    label: str
    score: float
    confidence: float
    positive_hits: list = field(default_factory=list)
    negative_hits: list = field(default_factory=list)

    def __str__(self):
        return (
            f"Metin      : {self.text}\n"
            f"Sonuç      : {self.label}\n"
            f"Skor       : {self.score:.2f}  (Güven: {self.confidence:.0%})\n"
            f"Pozitif    : {self.positive_hits}\n"
            f"Negatif    : {self.negative_hits}"
        )

    def to_dict(self):
        return {
            "text": self.text,
            "label": self.label,
            "score": round(self.score, 4),
            "confidence": round(self.confidence, 4),
            "positive_hits": self.positive_hits,
            "negative_hits": self.negative_hits,
        }


class LexiconSentimentAnalyzer:
    """Negasyon penceresi ve emoji desteği olan sözlük tabanlı analiz sınıfı."""

    def __init__(self, positive_words=None, negative_words=None,
                 negation_window=NEGATION_WINDOW):
        self.positive_words = set(positive_words or POSITIVE_WORDS)
        self.negative_words = set(negative_words or NEGATIVE_WORDS)
        self.negation_window = negation_window

    @staticmethod
    def _tokenize(text: str):
        # Emojileri koru, noktalamayı at
        emoji_pattern = re.findall(
            r"[\U0001F300-\U0001FAFF\u2600-\u27BF]", text
        )
        cleaned = re.sub(r"[^\wçğıöşüÇĞİÖŞÜ\s]", " ", text.lower(), flags=re.UNICODE)
        return cleaned.split(), emoji_pattern

    def _is_negated(self, tokens, index):
        start = max(0, index - self.negation_window)
        window = tokens[start:index]
        return any(w in NEGATORS for w in window)

    def _weight_from_window(self, tokens, index):
        start = max(0, index - self.negation_window)
        window = tokens[start:index]
        weight = 1.0
        for w in window:
            if w in INTENSIFIERS:
                weight *= INTENSIFIERS[w]
            elif w in DIMINISHERS:
                weight *= DIMINISHERS[w]
        return weight

    def analyze(self, text: str) -> SentimentResult:
        tokens, emojis = self._tokenize(text)
        score = 0.0
        positive_hits, negative_hits = [], []

        for i, word in enumerate(tokens):
            if word in self.positive_words:
                polarity = 1
            elif word in self.negative_words:
                polarity = -1
            else:
                continue

            weight = self._weight_from_window(tokens, i)
            if self._is_negated(tokens, i):
                polarity *= -1

            score += polarity * weight
            (positive_hits if polarity > 0 else negative_hits).append(word)

        for e in emojis:
            if e in POSITIVE_EMOJIS:
                score += 1
                positive_hits.append(e)
            elif e in NEGATIVE_EMOJIS:
                score -= 1
                negative_hits.append(e)

        total_hits = len(positive_hits) + len(negative_hits)
        normalized_score = max(-1.0, min(1.0, score / total_hits)) if total_hits else 0.0
        confidence = min(1.0, total_hits / 5) if total_hits else 0.0

        if normalized_score > 0.15:
            label = "Pozitif"
        elif normalized_score < -0.15:
            label = "Negatif"
        else:
            label = "Nötr"

        return SentimentResult(
            text=text, label=label, score=normalized_score,
            confidence=confidence,
            positive_hits=positive_hits, negative_hits=negative_hits,
        )

    def analyze_batch(self, texts):
        return [self.analyze(t) for t in texts]
