"""Offline checks for the upstream operation-index parser."""
import unittest
from audit_openai import Operations


class OperationsTest(unittest.TestCase):
    def test_only_reference_operation_links_are_collected_and_deduplicated(self):
        parser = Operations()
        parser.feed('''
          <a href="/api/reference/resources/responses/methods/create">Create</a>
          <a href="/api/reference/resources/responses/methods/create">Duplicate</a>
          <a href="/api/reference/resources/images/methods/generate">Images</a>
          <a href="/api/reference/resources/responses">Resource</a>
          <a href="https://example.com/api/reference/resources/x/methods/y">Other</a>
          <div href="/api/reference/resources/invalid/methods/create"></div>
        ''')
        self.assertEqual(parser.paths, {
            '/api/reference/resources/responses/methods/create',
            '/api/reference/resources/images/methods/generate',
        })

    def test_an_empty_or_changed_page_does_not_invent_operations(self):
        parser = Operations()
        parser.feed('<html><body>Access denied</body></html>')
        self.assertEqual(parser.paths, set())


if __name__ == '__main__':
    unittest.main()
