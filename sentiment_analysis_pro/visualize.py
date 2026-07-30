"""
visualize.py
=============
Sentiment analiz sonuçlarını grafikle görselleştirir.
- Duygu dağılımı (bar chart)
- Confusion matrix (karışıklık matrisi) - ML modeli değerlendirmesi için
"""

import os
import matplotlib
matplotlib.use("Agg")  # Ekran gerektirmeden dosyaya kaydetmek için
import matplotlib.pyplot as plt
import numpy as np


COLOR_MAP = {
    "Pozitif": "#2ecc71", "positive": "#2ecc71",
    "Negatif": "#e74c3c", "negative": "#e74c3c",
    "Nötr": "#95a5a6", "neutral": "#95a5a6",
}


def plot_sentiment_distribution(results, output_path="outputs/sentiment_distribution.png",
                                 title="Duygu Dağılımı"):
    """
    results: SentimentResult listesi ya da {"label": ...} sözlük listesi olabilir.
    """
    labels = [r.label if hasattr(r, "label") else r["label"] for r in results]
    unique_labels = sorted(set(labels), key=lambda x: labels.count(x), reverse=True)
    counts = [labels.count(l) for l in unique_labels]
    colors = [COLOR_MAP.get(l, "#3498db") for l in unique_labels]

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    plt.figure(figsize=(7, 5))
    bars = plt.bar(unique_labels, counts, color=colors)
    for bar, count in zip(bars, counts):
        plt.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.05,
                  str(count), ha="center", va="bottom", fontweight="bold")

    plt.title(title, fontsize=14, fontweight="bold")
    plt.ylabel("Metin Sayısı")
    plt.xlabel("Duygu")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"📊 Grafik kaydedildi: {output_path}")
    return output_path


def plot_confusion_matrix(matrix, labels, output_path="outputs/confusion_matrix.png",
                           title="Karışıklık Matrisi (Confusion Matrix)"):
    plt.figure(figsize=(6, 5))
    plt.imshow(matrix, interpolation="nearest", cmap="Blues")
    plt.title(title, fontsize=13, fontweight="bold")
    plt.colorbar()
    tick_marks = np.arange(len(labels))
    plt.xticks(tick_marks, labels, rotation=45)
    plt.yticks(tick_marks, labels)

    thresh = matrix.max() / 2.0
    for i in range(matrix.shape[0]):
        for j in range(matrix.shape[1]):
            plt.text(j, i, format(matrix[i, j], "d"),
                      ha="center", va="center",
                      color="white" if matrix[i, j] > thresh else "black")

    plt.ylabel("Gerçek Etiket")
    plt.xlabel("Tahmin Edilen Etiket")
    plt.tight_layout()

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"📊 Grafik kaydedildi: {output_path}")
    return output_path


def plot_score_histogram(results, output_path="outputs/score_histogram.png",
                          title="Skor Dağılımı (Sözlük Tabanlı Analiz)"):
    scores = [r.score if hasattr(r, "score") else r["score"] for r in results]
    plt.figure(figsize=(7, 5))
    plt.hist(scores, bins=15, color="#3498db", edgecolor="white")
    plt.axvline(0, color="black", linestyle="--", linewidth=1)
    plt.title(title, fontsize=14, fontweight="bold")
    plt.xlabel("Skor (-1: çok negatif, +1: çok pozitif)")
    plt.ylabel("Frekans")
    plt.tight_layout()

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"📊 Grafik kaydedildi: {output_path}")
    return output_path
