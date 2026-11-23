import unittest
from local_edesk.project_documents import timeline_seconds, timeline_clock


class TimelineTimesTests(unittest.TestCase):
    def test_excel_day_fractions_and_second_precision(self):
        self.assertEqual(timeline_clock(timeline_seconds(8/24)), '08:00:00')
        self.assertEqual(timeline_clock(timeline_seconds(10/24, duration=True)), '10:00:00')
        self.assertEqual(timeline_seconds('08:00:30'), 28830)
        self.assertEqual(timeline_clock(timeline_seconds('26:00:00', duration=True)), '26:00:00')

    def test_invalid_values_are_not_guessed(self):
        for value in [True, -1, float('nan'), None, '', '08:99:00', '10::00:00', 1]:
            self.assertIsNone(timeline_seconds(value))
        self.assertEqual(timeline_seconds(0), 0)


if __name__ == '__main__':
    unittest.main()
