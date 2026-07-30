"""
tests/test_sentiment.py
=========================
Basit birim testleri. Çalıştırmak için:
    python3 -m pytest tests/ -v
veya
    python3 tests/test_sentiment.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lexicon_analyzer import LexiconSentimentAnalyzer


class TestLexiconAnalyzer(unittest.TestCase):

    def setUp(self):
        self.analyzer = LexiconSentimentAnalyzer()

    def test_positive_sentence(self):
        result = self.analyzer.analyze("Bu ürün gerçekten harika, çok mutluyum!")
        self.assertEqual(result.label, "Pozitif")
        self.assertGreater(result.score, 0)

    def test_negative_sentence(self):
        result = self.analyzer.analyze("Hizmet çok kötüydü, berbat bir deneyimdi.")
        self.assertEqual(result.label, "Negatif")
        self.assertLess(result.score, 0)

    def test_neutral_sentence(self):
        result = self.analyzer.analyze("Bugün hava ne sıcak ne soğuk, normal bir gün.")
        self.assertEqual(result.label, "Nötr")

    def test_negation_flips_polarity(self):
        positive = self.analyzer.analyze("Bu film iyi.")
        negated = self.analyzer.analyze("Bu film hiç iyi değil.")
        self.assertEqual(positive.label, "Pozitif")
        self.assertEqual(negated.label, "Negatif")

    def test_intensifier_increases_score(self):
        normal = self.analyzer.analyze("İyi bir ürün.")
        intensified = self.analyzer.analyze("Çok iyi bir ürün.")
        self.assertGreaterEqual(intensified.score, normal.score)

    def test_empty_text(self):
        result = self.analyzer.analyze("")
        self.assertEqual(result.label, "Nötr")
        self.assertEqual(result.score, 0.0)

    def test_batch_analysis(self):
        texts = ["Harika!", "Berbat.", "Normal bir gün."]
        results = self.analyzer.analyze_batch(texts)
        self.assertEqual(len(results), 3)


if __name__ == "__main__":
    unittest.main()
