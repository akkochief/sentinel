# Sentiment Analiz Projesi (Gelişmiş Sürüm)

Türkçe/İngilizce metinler için **iki farklı motor** içeren kapsamlı bir
sentiment (duygu) analiz projesi:

1. **Sözlük Tabanlı Motor** (`lexicon_analyzer.py`) — Kurulum gerektirmez,
   anında çalışır. Negasyon (olumsuzlama) penceresi, güçlendirici/zayıflatıcı
   kelimeler ve emoji desteği içerir.
2. **Makine Öğrenmesi Motoru** (`ml_sentiment.py`) — TF-IDF + Lojistik
   Regresyon kullanır, verilen bir eğitim veri setinden **öğrenir**.

Ayrıca: komut satırı arayüzü (CLI), görselleştirme (grafikler), birim
testleri ve örnek bir eğitim veri seti dahildir.

---

## 📁 Proje Yapısı

```
sentiment_analysis_pro/
├── lexicon_analyzer.py     # Sözlük tabanlı analiz motoru
├── ml_sentiment.py         # TF-IDF + Lojistik Regresyon modeli
├── visualize.py            # Grafik / görselleştirme fonksiyonları
├── cli.py                  # Birleşik komut satırı arayüzü
├── data/
│   └── sample_dataset.csv  # Örnek eğitim verisi (55 cümle, TR/EN)
├── models/
│   └── model.pkl           # Eğitilmiş model (train sonrası oluşur)
├── outputs/                # Üretilen grafikler buraya kaydedilir
├── tests/
│   └── test_sentiment.py   # Birim testleri
├── requirements.txt
└── README.md
```

---

## ⚙️ Kurulum

```bash
cd sentiment_analysis_pro
pip install -r requirements.txt
```

> Sadece **sözlük tabanlı motoru** kullanacaksanız hiçbir kurulum
> gerekmez — `lexicon_analyzer.py` yalnızca Python standart kütüphanesini
> kullanır. ML motoru için `pandas`, `scikit-learn` ve `matplotlib`
> gereklidir.

---

## 🚀 Hızlı Başlangıç

### 1) Sözlük tabanlı tek metin analizi

```bash
python3 cli.py analyze "Bu ürün gerçekten harika, çok mutluyum!"
```

```
Metin      : Bu ürün gerçekten harika, çok mutluyum!
Sonuç      : Pozitif
Skor       : 1.00  (Güven: 40%)
Pozitif    : ['harika']
Negatif    : []
```

### 2) ML modelini eğitme

```bash
python3 cli.py train data/sample_dataset.csv --plot
```

Bu komut:
- `data/sample_dataset.csv` üzerinde modeli eğitir,
- `models/model.pkl` olarak kaydeder,
- `outputs/confusion_matrix.png` adında bir karışıklık matrisi grafiği üretir.

### 3) ML modeli ile tahmin

```bash
python3 cli.py analyze "Bu ürün çok kötü, hiç beğenmedim." --engine ml
```

```
Metin          : Bu ürün çok kötü, hiç beğenmedim.
Sonuç          : negative
Olasılıklar    : {'negative': 0.46, 'neutral': 0.21, 'positive': 0.32}
```

### 4) Toplu analiz + grafik

```bash
python3 cli.py batch data/sample_dataset.csv --plot
```

`outputs/sentiment_distribution.png` ve `outputs/score_histogram.png`
dosyaları oluşturulur.

---

## 🧠 Python Kodu İçinden Kullanım

### Sözlük tabanlı

```python
from lexicon_analyzer import LexiconSentimentAnalyzer

analyzer = LexiconSentimentAnalyzer()
result = analyzer.analyze("Bu film hiç iyi değildi, çok sıkıcıydı.")

print(result.label)        # "Negatif"
print(result.score)        # -1.0 ile 1.0 arası
print(result.to_dict())    # JSON'a çevrilebilir sözlük
```

### Makine öğrenmesi

```python
from ml_sentiment import MLSentimentAnalyzer

model = MLSentimentAnalyzer()
metrics = model.train("data/sample_dataset.csv")
print(f"Doğruluk: {metrics['accuracy']:.2%}")

model.save("models/model.pkl")

# Sonradan yükleme
model = MLSentimentAnalyzer.load("models/model.pkl")
print(model.predict("Harika bir ürün, tavsiye ederim!"))
```

### Görselleştirme

```python
from visualize import plot_sentiment_distribution
from lexicon_analyzer import LexiconSentimentAnalyzer

analyzer = LexiconSentimentAnalyzer()
results = analyzer.analyze_batch([
    "Harika!", "Berbat.", "Fena değil.", "Süper ötesi!"
])
plot_sentiment_distribution(results, "outputs/dagilim.png")
```

---

## 🔬 Nasıl Çalışır?

### Sözlük Tabanlı Motor
1. Metin küçük harfe çevrilir, kelimelere ayrılır, emojiler ayrıca yakalanır.
2. Her kelime pozitif/negatif sözlükleriyle karşılaştırılır.
3. Kelimeden önceki **3 kelimelik pencere** içinde:
   - Güçlendirici (`çok`, `gerçekten`, `aşırı`...) varsa skor büyütülür,
   - Zayıflatıcı (`biraz`, `az`...) varsa skor küçültülür,
   - Olumsuzlaştırıcı (`değil`, `hiç`, `yok`...) varsa polarite ters çevrilir.
4. Emoji skorları eklenir.
5. Toplam skor -1..1 arasına normalize edilir ve eşiklere göre etiketlenir.
6. **Güven (confidence)** skoru, bulunan duygu kelimesi sayısına göre hesaplanır.

### Makine Öğrenmesi Motoru
1. `TfidfVectorizer` metni kelime/bigram frekans vektörlerine çevirir
   (`ngram_range=(1,2)`, `max_features=5000`).
2. `LogisticRegression` (`class_weight="balanced"`) sınıflandırma yapar.
3. Eğitim sırasında veri `train_test_split` ile bölünür, test seti üzerinde
   `accuracy`, `precision`, `recall`, `f1-score` ve `confusion matrix`
   raporlanır.
4. Model `pickle` ile diske kaydedilir / diskten yüklenir.

---

## 📊 Örnek Veri Seti

`data/sample_dataset.csv` dosyasında `text,label` sütunlu, Türkçe ve
İngilizce karışık **55 örnek cümle** bulunur (positive / negative / neutral
dengeli dağılım). Kendi verinizle değiştirebilir veya genişletebilirsiniz:

```csv
text,label
"Ürün harikaydı, çok memnun kaldım.",positive
"Berbat bir deneyimdi.",negative
"Standart bir ürün, fazla bir şey yok.",neutral
```

> ⚠️ **Not:** Dahil edilen örnek veri seti küçük olduğu için (55 satır)
> ML modelinin test doğruluğu düşük çıkabilir. Gerçek kullanım için
> **en az birkaç yüz/bin örnek** içeren bir veri seti ile eğitmeniz
> önerilir. Sözlük tabanlı motor ise veri setinden bağımsız, her zaman
> tutarlı çalışır.

---

## 🧪 Testleri Çalıştırma

```bash
python3 -m unittest tests/test_sentiment.py -v
# veya pytest kuruluysa:
python3 -m pytest tests/ -v
```

---

## 🗂️ CLI Komutları Özeti

| Komut | Açıklama |
|---|---|
| `cli.py analyze "<metin>" [--engine lexicon\|ml]` | Tek metni analiz eder |
| `cli.py batch <dosya.csv/txt> [--engine ...] [--plot]` | Toplu analiz yapar |
| `cli.py train <veri.csv> [--output ...] [--plot]` | ML modelini eğitir |

---

## 🛠️ Genişletme Fikirleri

- `lexicon_analyzer.py` içindeki `POSITIVE_WORDS` / `NEGATIVE_WORDS`
  kümelerine yeni kelimeler ekleyin.
- `ml_sentiment.py` içinde `LogisticRegression` yerine `LinearSVC`,
  `RandomForestClassifier` veya `MultinomialNB` deneyin.
- Daha büyük ve gerçek bir veri seti (örneğin Türkçe ürün yorumları)
  ile modeli yeniden eğitin.
- Transformer tabanlı (BERT/DistilBERT) bir model entegre ederek
  doğruluğu artırın.
- `cli.py`'ye bir REST API katmanı (FastAPI/Flask) ekleyerek servis
  haline getirin.

---

## 📄 Lisans

Bu proje eğitim/örnek amaçlıdır. Dilediğiniz gibi kullanabilir,
değiştirebilir ve dağıtabilirsiniz.
