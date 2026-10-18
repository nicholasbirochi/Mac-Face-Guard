# Avisos de terceiros

## Glance

Adaptados de [Glance](https://github.com/jonnyoo/glance):

- `Sources/MacFaceGuardApp/KeystrokeInjector.swift` e `Sources/MacFaceGuardApp/LockMonitor.swift`;
- `Sources/MacFaceGuardApp/NotchOverlay/` (ilha do entalhe, animações e janela na tela de bloqueio), modificados: sem onboarding nem ajustes, ligados ao `UnlockCoordinator`;
- `Resources/Unlock/` (`unlockanimation.mp4`, `unsuccessfulunlockanimation.mp4`, `unlockstatic.png`), recoloridos de verde por `scripts/tint-glance-assets.sh`.

`NotchOverlay/NotchSkyLight.swift` usa a técnica de espaço SkyLight que o Glance adaptou de [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) (MIT).

```
MIT License

Copyright (c) 2026 Jonathan Zhou

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
