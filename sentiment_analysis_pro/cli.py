"""
cli.py
=======
Sözlük tabanlı ve ML tabanlı analizi tek bir komut satırı aracında birleştirir.

Örnekler:
    # Sözlük tabanlı, tek metin
    python3 cli.py analyze "Bu ürün harika!"

    # ML tabanlı, tek metin (önce model eğitilmiş olmalı)
    python3 cli.py analyze "Bu ürün harika!" --engine ml

    # Dosyadan toplu analiz + grafik
    python3 cli.py batch data/sample_dataset.csv --plot

    # Modeli eğitme
    python3 cli.py train data/sample_dataset.csv
"""

import argparse
import os
import sys
import pandas as pd

from lexicon_analyzer import LexiconSentimentAnalyzer
from ml_sentiment import MLSentimentAnalyzer
from visualize import plot_sentiment_distribution, plot_confusion_matrix, plot_score_histogram

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MODEL_PATH = os.path.join(BASE_DIR, "models", "model.pkl")


def cmd_analyze(args):
    if args.engine == "lexicon":
        analyzer = LexiconSentimentAnalyzer()
        result = analyzer.analyze(args.text)
        print(result)
    else:
        if not os.path.exists(args.model):
            print(f"❌ Model bulunamadı: {args.model}\n"
                  f"   Önce şunu çalıştırın: python3 cli.py train data/sample_dataset.csv")
            sys.exit(1)
        model = MLSentimentAnalyzer.load(args.model)
        result = model.predict(args.text)
        print(f"Metin          : {result['text']}")
        print(f"Sonuç          : {result['label']}")
        print(f"Olasılıklar    : {result['probabilities']}")


def cmd_batch(args):
    ext = os.path.splitext(args.path)[1].lower()
    if ext == ".csv":
        df = pd.read_csv(args.path)
        texts = df["text"].tolist()
    else:
        with open(args.path, "r", encoding="utf-8") as f:
            texts = [line.strip() for line in f if line.strip()]

    if args.engine == "lexicon":
        analyzer = LexiconSentimentAnalyzer()
        results = analyzer.analyze_batch(texts)
        for r in results:
            print(r)
            print("-" * 40)
        if args.plot:
            os.makedirs(os.path.join(BASE_DIR, "outputs"), exist_ok=True)
            plot_sentiment_distribution(
                results, os.path.join(BASE_DIR, "outputs", "sentiment_distribution.png"))
            plot_score_histogram(
                results, os.path.join(BASE_DIR, "outputs", "score_histogram.png"))
    else:
        if not os.path.exists(args.model):
            print(f"❌ Model bulunamadı: {args.model}")
            sys.exit(1)
        model = MLSentimentAnalyzer.load(args.model)
        results = model.predict_batch(texts)
        for r in results:
            print(f"{r['label']:10s} | {r['text']}")
        if args.plot:
            os.makedirs(os.path.join(BASE_DIR, "outputs"), exist_ok=True)
            plot_sentiment_distribution(
                results, os.path.join(BASE_DIR, "outputs", "sentiment_distribution.png"))


def cmd_train(args):
    model = MLSentimentAnalyzer()
    metrics = model.train(args.csv_path, test_size=args.test_size)
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    model.save(args.output)

    if args.plot:
        os.makedirs(os.path.join(BASE_DIR, "outputs"), exist_ok=True)
        plot_confusion_matrix(
            metrics["confusion_matrix"], metrics["labels"],
            os.path.join(BASE_DIR, "outputs", "confusion_matrix.png"))


def build_parser():
    parser = argparse.ArgumentParser(
        description="Sentiment Analiz Aracı (Sözlük tabanlı + Makine Öğrenmesi)"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_analyze = sub.add_parser("analyze", help="Tek bir metni analiz et")
    p_analyze.add_argument("text", help="Analiz edilecek metin")
    p_analyze.add_argument("--engine", choices=["lexicon", "ml"], default="lexicon")
    p_analyze.add_argument("--model", default=DEFAULT_MODEL_PATH)
    p_analyze.set_defaults(func=cmd_analyze)

    p_batch = sub.add_parser("batch", help="Dosyadan toplu analiz yap (csv veya txt)")
    p_batch.add_argument("path", help="CSV (text sütunlu) veya her satırda bir metin olan .txt dosyası")
    p_batch.add_argument("--engine", choices=["lexicon", "ml"], default="lexicon")
    p_batch.add_argument("--model", default=DEFAULT_MODEL_PATH)
    p_batch.add_argument("--plot", action="store_true", help="Sonuçları grafikle görselleştir")
    p_batch.set_defaults(func=cmd_batch)

    p_train = sub.add_parser("train", help="ML modelini eğit ve kaydet")
    p_train.add_argument("csv_path", help="Eğitim verisi (text,label sütunlu CSV)")
    p_train.add_argument("--output", default=DEFAULT_MODEL_PATH)
    p_train.add_argument("--test-size", type=float, default=0.2)
    p_train.add_argument("--plot", action="store_true", help="Confusion matrix grafiği oluştur")
    p_train.set_defaults(func=cmd_train)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
