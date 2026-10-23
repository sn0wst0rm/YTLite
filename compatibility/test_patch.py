import struct
import unittest
from patch_app import NATIVE_SHARE, ORIGINAL, PATCHED, patch_native_share

class PatchTests(unittest.TestCase):
    def image(self):
        b = bytearray(256)
        b[:4] = b'\xcf\xfa\xed\xfe'
        struct.pack_into('<I', b, 16, 1)
        struct.pack_into('<II', b, 32, 0x19, 72)
        struct.pack_into('<QQQQ', b, 56, NATIVE_SHARE, 32, 128, 32)
        b[128:140] = ORIGINAL
        return b

    def test_maps_virtual_address_and_preserves_other_bytes(self):
        original = self.image()
        result = patch_native_share(original)
        self.assertEqual(result[128:140], PATCHED)
        self.assertEqual(result[:128], original[:128])
        self.assertEqual(result[140:], original[140:])

    def test_idempotent(self):
        result = patch_native_share(self.image())
        self.assertEqual(patch_native_share(result), result)

    def test_rejects_other_binary(self):
        b = self.image()
        b[128] ^= 1
        with self.assertRaises(ValueError): patch_native_share(b)

    def test_rejects_wrong_format(self):
        with self.assertRaises(ValueError): patch_native_share(b'not a Mach-O')

if __name__ == '__main__': unittest.main()
