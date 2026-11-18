# g_design

The shared layer for the immersive minimalism direction (decided 7 Nov 2026).

Rules the widgets enforce:

1. Content is the background, edge to edge under transparent system bars.
2. Chrome floats: `FloatHeader` at the top, `FloatingNav` 12 dp off the bottom. No app bars.
3. One raised surface: `ContentSheet`. Everything else is `EdgeRow` with hairlines.
4. One big figure (`HeroFigure`) and one primary action per screen.
5. Colour means state only. Each app keeps its own palette by supplying `GDesignTheme`.

An app registers `GDesignTheme` in its `ThemeData.extensions`. Wrap the tree in
`GEffects(lite: true)` on low-memory phones to swap blur for solid surfaces.
