import unittest
from .csv_converter import csv

class CSVConverterTest(unittest.TestCase):

    def test_csv(self):
        headers = ['host_name', 'prop1', 'prop2']
        lines = ['one.example.org,sweet,potato', 'two.example.com,happy,hippo']

        result = csv('csv_test', headers, lines)
        
        self.assertEqual(len(result), 2)
        h1, h2 = result
        self.assertEqual(h1['host']['name'], 'one.example.org')
        self.assertEqual(h1['host']['version'], 1)
        self.assertEqual(h1['host']['csv_test'], {'prop1': 'sweet', 'prop2': 'potato'})
      
        self.assertEqual(h2['host']['name'], 'two.example.com')
        self.assertEqual(h2['host']['version'], 1)
        self.assertEqual(h2['host']['csv_test'], {'prop1': 'happy', 'prop2': 'hippo'})

