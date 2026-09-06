# raylib 6.0 image/text fixes

The package keeps its pinned 6.0 headers and applies
`image-text-security.patch` to the native implementation before building.
Both dependency manifests pin the patch SHA-256. These are altered upstream
sources, not an unmodified raylib release.

The selected upstream fixes and follow-up corrections are:

- [ImageFromImage bounds](https://github.com/raysan5/raylib/commit/c31666fe2a5c1e166353807a1e9affcfb165b4a9)
  and [valid edge rectangles](https://github.com/raysan5/raylib/commit/5de8c3521fc909e7f1baa5573329dfe7019e6ab7).
- [Compressed-image rejection](https://github.com/raysan5/raylib/commit/5b1445b38195b739faaa9e211be2bd272bb77f00).
- [Pixel allocation sizes](https://github.com/raysan5/raylib/commit/cfe56d97ea6b0cf29f4c80f1ebc9e704921a2a10)
  and [rotation correction](https://github.com/raysan5/raylib/commit/a9a0c046f1f8850de1f5d51f7b5d44895fd46b4c).
- [Text bounds](https://github.com/raysan5/raylib/commit/ebec978443efe8d7a46723fb1e4479422e950006),
  [position zero](https://github.com/raysan5/raylib/commit/b631fb3d052b767ccd0281b0d008cdaf810b5267),
  and [insertion copies](https://github.com/raysan5/raylib/commit/3ea8b9298f75513388cde1aef7bb7af614cd3ec4).

The backport also checks positive allocation sizes before calling calloc:
C permits a non-null result for a zero-byte allocation. Rectangle bounds use
double arithmetic before integer conversion, avoiding overflow in the bounds
check itself. These are local corrections to the selected upstream changes.
The 6.1 development API renames and unrelated drawing changes are excluded.

The existing raw API test covers rejected outside crops, valid whole-image
crops, empty image allocation, and text insertion/substrings. The first run
against the old linked archive failed the outside crop, empty allocation,
and middle insertion checks; the patched archive passes. Existing rotation,
image mutation, and deterministic PNG checks also pass.
