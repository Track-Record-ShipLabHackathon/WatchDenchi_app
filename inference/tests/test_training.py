import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from predictor import MODEL_PATH, Predictor
from train import train


class TrainingTests(unittest.TestCase):
    def test_model_can_be_relearned_from_checked_in_data(self):
        saved = json.loads(MODEL_PATH.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            candidate = train(Path(directory))
            self.assertEqual(candidate["tree"], saved["tree"])
            self.assertEqual(candidate["data_sha256"], saved["data_sha256"])
            self.assertEqual(candidate["evaluation"], saved["evaluation"])
            predictor = Predictor(Path(directory) / "mouse_tree.json")
            self.assertEqual(predictor.model["training_rows"], 15)
        evaluation = saved["evaluation"]
        self.assertEqual(evaluation["method"], "leave_one_product_family_out")
        self.assertFalse(evaluation["real_world_replacement_accuracy_validated"])


if __name__ == "__main__":
    unittest.main()
