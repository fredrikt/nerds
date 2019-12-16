# -*- coding: utf-8 -*-
import unittest
from utils import find_all


class FindAllTest(unittest.TestCase):

    def test_direct(self):
        data = {
            'test': 'best',
        }
        self.assertEqual(find_all('test', data), ['best'])

    def test_nested(self):
        data = {
            'test': [
                {'hest': 1},
                {'hest': 2},
            ],
            'hest': 3,
        }
        self.assertEqual(set(find_all('hest', data)), set([1, 2, 3]))
