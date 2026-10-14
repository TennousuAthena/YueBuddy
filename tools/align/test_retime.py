"""Timeline rebuild: islands, swallowed words, and character clocks."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from retime import (  # noqa: E402
    assign_islands,
    build_timeline,
    carve_unclaimed_tails,
    plan_recording,
)


def _item(text, start=None, end=None):
    row = {"id": text, "cantonese": text}
    if start is not None:
        row["clip"] = {"startMs": start, "endMs": end}
    return row


class AssignTests(unittest.TestCase):
    def test_short_card_does_not_keep_the_next_word(self):
        items = [_item("做gym"), _item("健身", 20120, 22549)]
        islands = [(20200, 20810), (21830, 22480)]
        # Labels are already canonical, matching asr_chars().
        labels = ["做gym", "健身"]
        clips = [None, (20120, 22549)]
        shares = assign_islands(items, islands, labels, clips)
        self.assertEqual(shares[0], [0])
        self.assertEqual(shares[1], [1])

    def test_cut_sentence_keeps_the_whole_island(self):
        items = [
            _item("天氣好嘅話有時會去海旁跑步，一嚟可以操肌", 8471, 14339),
            _item("二嚟做完運動出一身汗好舒服㗎", 14339, 16730),
        ]
        islands = [(8550, 11270), (11950, 13200), (13870, 16660)]
        labels = ["天氣好的話有時會去海旁跑步", "一嚟可以操肌", "二嚟做完運動出一身汗"]
        clips = [(8471, 14339), (14339, 16730)]
        shares = assign_islands(items, islands, labels, clips)
        self.assertIn(0, shares[0])
        self.assertIn(0, shares[1])
        self.assertEqual(shares[2], [1])

    def test_one_syllable_mishear_stays_on_the_card_that_covers_it(self):
        items = [
            _item("二十／廿", 15853, 17770),
            _item("三十／卅", 18321, 20232),
        ]
        islands = [(15890, 16310), (17200, 17710), (18350, 20210)]
        labels = ["零", "三", "三十"]
        clips = [(15853, 17770), (18321, 20232)]
        shares = assign_islands(items, islands, labels, clips)
        self.assertEqual(shares[0], [0])
        self.assertEqual(shares[1], [0])
        self.assertEqual(shares[2], [1])

    def test_two_sentences_in_one_island_split(self):
        items = [
            _item("我都未試過喺香港唱K", 14380, 16440),
            _item("你預埋我吖"),
        ]
        islands = [(14380, 17250)]
        labels = ["我都未试过喺香港唱k你預埋我"]
        clips = [(14380, 16440), None]
        shares = assign_islands(items, islands, labels, clips)
        chars = [
            ("我", 14.50, 14.70),
            ("都", 14.70, 14.90),
            ("未", 14.90, 15.10),
            ("试", 15.10, 15.30),
            ("过", 15.30, 15.50),
            ("喺", 15.50, 15.70),
            ("香", 15.70, 15.90),
            ("港", 15.90, 16.10),
            ("唱", 16.10, 16.30),
            ("k", 16.30, 16.45),
            ("你", 16.55, 16.75),
            ("預", 16.75, 16.95),
            ("埋", 16.95, 17.10),
            ("我", 17.10, 17.25),
        ]
        carves = carve_unclaimed_tails(
            items, islands, chars, shares, [True, True]
        )
        self.assertEqual(len(carves), 1)
        _island, tail_item, cut, end = carves[0]
        self.assertEqual(tail_item, 1)
        self.assertGreater(cut, 16000)
        self.assertEqual(end, 17250)

    def test_identical_clip_stays_shared(self):
        items = [_item("我搭", 20570, 21780), _item("巴士", 20570, 21780)]
        islands = [(20640, 21720)]
        labels = ["我搭巴士"]
        clips = [(20570, 21780), (20570, 21780)]
        shares = assign_islands(items, islands, labels, clips)
        self.assertCountEqual(shares[0], [0, 1])


class TimelineTests(unittest.TestCase):
    def test_characters_light_inside_speech_and_not_together(self):
        # Whisper started "二" before the island; the old cut piled
        # 二/嚟/做 onto one millisecond. The island clock keeps them apart.
        islands = [(13870, 16660)]
        chars = [
            ("二", 13.56, 13.98),
            ("嚟", 13.98, 14.12),
            ("做", 14.12, 14.32),
            ("完", 14.32, 14.50),
            ("運", 14.50, 14.72),
            ("動", 14.72, 15.00),
            ("出", 15.00, 15.22),
            ("一", 15.22, 15.38),
            ("身", 15.38, 15.54),
            ("汗", 15.54, 15.84),
            ("好", 15.96, 16.06),
            ("舒", 16.22, 16.38),
            ("服", 16.38, 16.55),
            ("㗎", 16.55, 16.66),
        ]
        timeline = build_timeline("二嚟做完運動出一身汗好舒服㗎", chars, islands)
        self.assertIsNotNone(timeline)
        starts = timeline["w"][0::2]
        self.assertEqual(len(starts), len(timeline["t"]))
        self.assertTrue(all(starts[i] - starts[i - 1] >= 40 for i in range(1, len(starts))))
        self.assertTrue(all(13870 <= s < 16660 for s in starts))
        # 二 is the onset, not a pile at the old cut (14339).
        self.assertLess(starts[0], 14200)
        self.assertGreater(starts[2], starts[0])

    def test_pause_does_not_advance_the_highlight(self):
        islands = [(820, 1470), (1940, 3710)]
        chars = [
            ("係", 0.90, 1.10),
            ("呢", 1.10, 1.30),
            ("你", 2.02, 2.20),
            ("平", 2.20, 2.40),
            ("時", 2.40, 2.60),
        ]
        timeline = build_timeline("係呢你平時", chars, islands)
        starts = timeline["w"][0::2]
        self.assertTrue(all(s < 1470 or s >= 1940 for s in starts))
        self.assertLess(starts[1], 1470)
        self.assertGreaterEqual(starts[2], 1940)

    def test_swallowed_word_is_its_own_clip(self):
        items = [_item("做gym"), _item("健身", 20120, 22549)]
        islands = [(20200, 20810), (21830, 22480)]
        chars = [
            ("做", 20.30, 20.55),
            ("gym", 20.55, 20.80),
            ("健", 21.90, 22.20),
            ("身", 22.20, 22.45),
        ]
        results, _labels, _shares = plan_recording(items, islands, chars, 0)
        gym, fit = results
        self.assertIsNotNone(gym)
        self.assertIsNotNone(fit)
        self.assertLess(gym["endMs"], 21200)
        self.assertGreater(fit["startMs"], 21400)
        gym_starts = gym["w"][0::2]
        self.assertTrue(all(20200 <= s < 20810 for s in gym_starts))
        self.assertGreaterEqual(gym_starts[1] - gym_starts[0], 40)


if __name__ == "__main__":
    unittest.main()
