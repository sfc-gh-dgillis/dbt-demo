import unittest
from cmd.pysrc.concatenate_dict_values import concatenate_dict_values


class TestConcatenateDictValues(unittest.TestCase):
    def test_basic(self):
        d = {'b': '2', 'a': '1', 'c': '3'}
        self.assertEqual(concatenate_dict_values(d), '1-2-3')

    def test_with_nulls(self):
        d = {'a': None, 'b': '', 'c': []}
        expected = '_dbt_utils_surrogate_key_null_-_dbt_utils_surrogate_key_null_-_dbt_utils_surrogate_key_null_'
        self.assertEqual(concatenate_dict_values(d), expected)

    def test_mixed(self):
        d = {'a': 'foo', 'b': '', 'c': 0}
        expected = 'foo-_dbt_utils_surrogate_key_null_-0'
        self.assertEqual(concatenate_dict_values(d), expected)

    def test_custom_null(self):
        d = {'a': None, 'b': 'bar'}
        self.assertEqual(concatenate_dict_values(d, default_null_value='NULL'), 'NULL-bar')


    def test_sorting(self):
        d = {'a': None, 'b': 'bar'}
        self.assertEqual(concatenate_dict_values(d, default_null_value='NULL'), 'NULL-bar')


if __name__ == '__main__':
    unittest.main()