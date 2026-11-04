"""Check the actual PNG bytes used by the client and storage fixtures."""
import base64
import re
import struct
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = [
    'tool/interop/server.dart',
    'examples/review_cases/openai_hosted.dart',
    'examples/review_cases/openrouter_images.dart',
    'examples/review_cases/output_media_client.dart',
    'examples/serverpod/agent_weave_demo_server/test/integration/output_media_test.dart',
    'examples/serverpod/agent_weave_demo_server/test/integration/openrouter_images_test.dart',
]


class MediaFixtureTest(unittest.TestCase):
    def test_inline_images_are_complete_decodable_one_pixel_pngs(self):
        for filename in FIXTURES:
            with self.subTest(file=filename):
                matches = re.findall(r'iVBORw0KGgo[A-Za-z0-9+/=]+',
                                     (ROOT / filename).read_text())
                self.assertTrue(matches)
                self.assertEqual(len(set(matches)), 1)
                png = base64.b64decode(matches[0], validate=True)
                self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
                offset, tags, pixels = 8, [], bytearray()
                while offset < len(png):
                    length, = struct.unpack('>I', png[offset:offset + 4])
                    tag = png[offset + 4:offset + 8]
                    data = png[offset + 8:offset + 8 + length]
                    checksum, = struct.unpack('>I', png[offset + 8 + length:offset + 12 + length])
                    self.assertEqual(zlib.crc32(tag + data), checksum)
                    if tag == b'IHDR':
                        self.assertEqual(struct.unpack('>IIBBBBB', data), (1, 1, 8, 6, 0, 0, 0))
                    elif tag == b'IDAT':
                        pixels.extend(data)
                    elif tag == b'IEND':
                        self.assertEqual(data, b'')
                    tags.append(tag)
                    offset += length + 12
                self.assertEqual(offset, len(png))
                self.assertEqual(tags, [b'IHDR', b'IDAT', b'IEND'])
                self.assertEqual(zlib.decompress(pixels), b'\x00\xff\x00\x00\xff')


if __name__ == '__main__':
    unittest.main()
