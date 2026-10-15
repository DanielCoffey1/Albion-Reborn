# Artwork provenance

The cards display promotional cover art from the official Xbox store listings. The first chapter uses Fable Anniversary's cover to represent Fable I; this does not select or install that edition.

- [Fable Anniversary](https://www.xbox.com/en-US/games/store/_/C2Q32JM0BPZL)
- [Fable II](https://www.xbox.com/en-US/games/store/Fable-II/C2WKJJ9F5936)
- [Fable III](https://www.xbox.com/en-us/games/store/Fable-III/BR46KM4D5B9L)

`art-sources.json` records the exact Microsoft image CDN URLs. `Fetch-Art.ps1` downloads the three images into ignored `assets/covers/`. They remain local, are not included in Git, and retain their owners' copyrights; the launcher's MIT license does not cover them. The WPF image viewport crops the platform banner and letterboxing at display time without altering the downloaded files.

The interface, decorative guild-style monogram, gradients, borders, and hover effects are original vector/code design. No game files are extracted or uploaded. Existing cached covers work offline. If artwork cannot be downloaded, the launcher still works with its styled background and game labels.
