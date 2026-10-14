"""Regression checks for rotated RLE storage, separate from ANI mirroring."""
import importlib.util
from pathlib import Path
import struct
import unittest
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('decoder', ROOT / 'analysis/decode_assets.py')
DECODER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DECODER)


class RotatedStorageTests(unittest.TestCase):
    palette = struct.pack('>4H', 0, 0xF800, 0x07E0, 0x001F)
    # Asymmetric 2×3 intended image, and the same pixels stored clockwise.
    upright = bytes([1, 2, 2, 3, 3, 1])
    stored = bytes([3, 2, 1, 1, 3, 2])

    def rle(self, pixels):
        return b''.join(bytes([value, 1]) for value in pixels)

    def single(self, typ, width, height, pixels):
        data = self.rle(pixels)
        return bytes([typ, width, height]) + struct.pack('>I', len(data)) + data + bytes([4]) + self.palette

    def frame(self, typ, width, height, pixels):
        data = self.rle(pixels)
        return bytes([typ, width, height]) + struct.pack('>I', len(data)) + data

    def test_single_image_type3_restores_size_and_pixel_positions(self):
        normal = DECODER.decode_img(self.single(2, 2, 3, self.upright))
        rotated = DECODER.decode_img(self.single(3, 3, 2, self.stored))
        self.assertEqual(rotated.size, (2, 3))
        np.testing.assert_array_equal(np.asarray(rotated), np.asarray(normal))
        self.assertEqual(rotated.getpixel((0, 0)), (255, 0, 0, 255))
        self.assertEqual(rotated.getpixel((1, 2)), (255, 0, 0, 255))

    def test_mixed_spriteset_normalizes_each_frame_independently(self):
        blob = bytes([1, 4]) + self.palette + bytes([2])
        blob += self.frame(2, 2, 3, self.upright)
        blob += self.frame(3, 3, 2, self.stored)
        frames = DECODER.decode_imgs(blob)
        self.assertEqual([image.size for image in frames], [(2, 3), (2, 3)])
        np.testing.assert_array_equal(np.asarray(frames[0]), np.asarray(frames[1]))

    def test_original_mage_head_and_feet_have_display_dimensions(self):
        blob = (ROOT / 'analysis/unpacked/ssjx/hero/mfst2.imgs').read_bytes()
        head, feet = DECODER.decode_imgs(blob)
        self.assertEqual(head.size, (42, 43))
        self.assertEqual(feet.size, (20, 16))

    def test_title_is_upright_in_decoder(self):
        image = DECODER.decode_img((ROOT / 'analysis/unpacked/ssjx/biaoti.img').read_bytes())
        self.assertEqual(image.size, (196, 92))


if __name__ == '__main__':
    unittest.main()
