#!/usr/bin/env python3
"""Apply the tested 21.42.4 / YTLite 5.2b4 compatibility fixes before signing."""
import argparse
import pathlib
import plistlib
import struct
import subprocess

NATIVE_SHARE = 0x2CF70
ORIGINAL = bytes.fromhex('fa67bba9f85f01a9f65702a9')
delta = (0xE6A000 >> 12) - (NATIVE_SHARE >> 12)
PATCHED = struct.pack('<III', 0x90000008 | ((delta & 3) << 29) |
                      (((delta >> 2) & 0x7ffff) << 5), 0xf9425508, 0xd61f0100)


def patch_native_share(data):
    data = bytearray(data)
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected thin arm64 YTLite 5.2b4 Mach-O')
    off = 32
    target = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        cmd, size = struct.unpack_from('<II', data, off)
        if size < 8 or off + size > len(data):
            raise ValueError('Invalid Mach-O load command')
        if cmd == 0x19:
            vm, _, fileoff, filesize = struct.unpack_from('<QQQQ', data, off + 24)
            if vm <= NATIVE_SHARE and NATIVE_SHARE + 12 <= vm + filesize:
                target = fileoff + NATIVE_SHARE - vm
        off += size
    if target is None or data[target:target + 12] not in (ORIGINAL, PATCHED):
        raise ValueError('Unsupported YTLite binary: expected 5.2b4 native-share hook')
    data[target:target + 12] = PATCHED
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path, help='Extracted YouTube.app, already injected with YTLite 5.2b4')
    parser.add_argument('--insert-dylib', required=True, help='Path to insert_dylib (also bundled with cyan)')
    args = parser.parse_args()
    info = plistlib.loads((args.app / 'Info.plist').read_bytes())
    if info.get('CFBundleShortVersionString') != '21.42.4':
        parser.error('Only YouTube 21.42.4 has been validated')
    tweak = args.app / 'Frameworks/YTLite.dylib'
    patched = patch_native_share(tweak.read_bytes())  # Validate before changing files.
    dylib = args.app / 'Frameworks/YouTubeCompatibility.dylib'
    subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-arch', 'arm64',
                    '-miphoneos-version-min=15.0', '-dynamiclib', '-fobjc-arc',
                    '-framework', 'Foundation', '-framework', 'UIKit', '-install_name', '@rpath/YouTubeCompatibility.dylib',
                    str(pathlib.Path(__file__).with_name('YouTubeCompatibility.m')),
                    '-o', str(dylib)], check=True)
    main_binary = args.app / info['CFBundleExecutable']
    libraries = subprocess.check_output(['xcrun', 'otool', '-L', str(main_binary)], text=True)
    if '@rpath/YouTubeCompatibility.dylib' not in libraries:
        subprocess.run([args.insert_dylib, '--weak', '--inplace', '--all-yes',
                        '@rpath/YouTubeCompatibility.dylib', str(main_binary)], check=True)
    tweak.write_bytes(patched)
    print('Compatibility fixes applied. Re-sign all nested code and the app before installation.')


if __name__ == '__main__':
    main()
