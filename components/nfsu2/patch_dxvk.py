"""Make Pinnacle's DXVK d3d9.dll load vulkan-1.dll instead of winevulkan.dll.

DXVK tries winevulkan.dll first when it runs under Wine, which skips the
Khronos loader and so the ReShade Vulkan layer. Renaming that import string
to a DLL that does not exist makes DXVK fall back to vulkan-1.dll.

Usage: patch_dxvk.py SOURCE_DLL OUTPUT_DLL
"""

import sys

ORIGINAL = b"winevulkan.dll\0"
PATCHED = b"winevulkaX.dll\0"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    source, output = sys.argv[1:]
    with open(source, "rb") as f:
        data = f.read()
    count = data.count(ORIGINAL)
    if count == 0:
        print(f"ERROR: {source} has no {ORIGINAL[:-1].decode()} string; not a DXVK d3d9.dll?", file=sys.stderr)
        return 1
    with open(output, "wb") as f:
        f.write(data.replace(ORIGINAL, PATCHED))
    print(f"Patched {count} winevulkan.dll reference(s) into {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
