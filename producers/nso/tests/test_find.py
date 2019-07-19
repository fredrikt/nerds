# -*- coding: utf-8 -*-
import unittest
from utils import find


class FindTest(unittest.TestCase):

    def test_direct(self):
        data = {
            'test': 'hest',
        }
        self.assertEqual(find('test', data), 'hest')

    def test_simple_nested(self):
        data = {
            'test': {
                'hest': {
                    'test': 'best'
                }
            }
        }

        self.assertEqual(find('test.hest.test', data), 'best')
        self.assertIn('test', find('test.hest', data))

    def test_delimiter(self):
        data = {
            'test.hest': {
                'test': 'sweet'
            }
        }

        self.assertEqual(find('test.hest/test', data, '/'), 'sweet')
