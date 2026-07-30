"""
ml_sentiment.py
================
TF-IDF + Lojistik Regresyon tabanlı, veriden ÖĞRENEN sentiment sınıflandırıcı.
scikit-learn kullanır. Eğitim verisi CSV formatında (text,label) olmalı.

Kullanım:
    from ml_sentiment import MLSentimentAnalyzer

    model = MLSentimentAnalyzer()
    model.train("data/sample_dataset.csv")
    model.save("models/model.pkl")

    # Sonradan yüklemek için:
    model = MLSentimentAnalyzer.load("models/model.pkl")
    print(model.predict("Bu ürün harika!"))
"""

import pickle
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.pipeline import Pipeline


class MLSentimentAnalyzer:
    def __init__(self, max_features=5000, ngram_range=(1, 2), C=2.0):
        self.pipeline = Pipeline([
            ("tfidf", TfidfVectorizer(
                max_features=max_features,
                ngram_range=ngram_range,
                sublinear_tf=True,
            )),
            ("clf", LogisticRegression(
                C=C, max_iter=1000, class_weight="balanced"
            )),
        ])
        self.is_trained = False
        self.classes_ = None

    def train(self, csv_path: str, test_size: float = 0.2, random_state: int = 42, verbose: bool = True):
        """CSV dosyasından (text,label sütunları) modeli eğitir ve
        bir test bölmesi üzerinde performans raporu döndürür."""
        df = pd.read_csv(csv_path)
        if "text" not in df.columns or "label" not in df.columns:
            raise ValueError("CSV dosyası 'text' ve 'label' sütunlarını içermelidir.")

        X_train, X_test, y_train, y_test = train_test_split(
            df["text"], df["label"],
            test_size=test_size, random_state=random_state, stratify=df["label"]
        )

        self.pipeline.fit(X_train, y_train)
        self.is_trained = True
        self.classes_ = self.pipeline.named_steps["clf"].classes_

        y_pred = self.pipeline.predict(X_test)
        report = classification_report(y_test, y_pred, output_dict=True)
        matrix = confusion_matrix(y_test, y_pred, labels=self.classes_)
        acc = accuracy_score(y_test, y_pred)

        if verbose:
            print(f"✅ Eğitim tamamlandı. Test doğruluğu (accuracy): {acc:.2%}\n")
            print(classification_report(y_test, y_pred))

        return {
            "accuracy": acc,
            "report": report,
            "confusion_matrix": matrix,
            "labels": list(self.classes_),
            "y_test": list(y_test),
            "y_pred": list(y_pred),
        }

    def predict(self, text: str):
        if not self.is_trained:
            raise RuntimeError("Model eğitilmedi. Önce train() veya load() çağırın.")
        label = self.pipeline.predict([text])[0]
        proba = self.pipeline.predict_proba([text])[0]
        proba_dict = dict(zip(self.pipeline.named_steps["clf"].classes_, proba))
        return {
            "text": text,
            "label": label,
            "probabilities": {k: round(float(v), 4) for k, v in proba_dict.items()},
        }

    def predict_batch(self, texts):
        return [self.predict(t) for t in texts]

    def save(self, path: str):
        with open(path, "wb") as f:
            pickle.dump(self, f)
        print(f"💾 Model kaydedildi: {path}")

    @staticmethod
    def load(path: str) -> "MLSentimentAnalyzer":
        with open(path, "rb") as f:
            model = pickle.load(f)
        return model


if __name__ == "__main__":
    import os
    base = os.path.dirname(__file__)
    model = MLSentimentAnalyzer()
    metrics = model.train(os.path.join(base, "data", "sample_dataset.csv"))
    os.makedirs(os.path.join(base, "models"), exist_ok=True)
    model.save(os.path.join(base, "models", "model.pkl"))

    print("\nÖrnek tahminler:")
    for t in [
        "Bu ürün gerçekten harika, çok memnun kaldım!",
        "Kesinlikle tavsiye etmiyorum, berbat bir alışverişti.",
        "Standart bir ürün, fazla bir beklentim yoktu.",
    ]:
        print(model.predict(t))
