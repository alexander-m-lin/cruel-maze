# Fear Eater's textures

Recoloured copies of generated textures, made in Studio with EditableImage, sent here with
`tools/textures/receive.py` and uploaded with the Studio MCP's `upload_image`.

| File | Asset | Used on | Made from |
|---|---|---|---|
| `cloak.png` | rbxassetid://71711427533090 | `FearEaterRig.Cloak` (TextureContent) | the generated cloak's texture, greyscale, value = 0.04 + luminance × 0.32 (near black, folds kept) |
| `body.png` | rbxassetid://102301039166501 | `FearEaterRig.Body` (TextureContent) | the cloak's inner body texture, same recolour |
| `arm.png` | rbxassetid://89506029749026 | forearms and hands (SurfaceAppearance ColorMap) | the stand-in monster's purple ColorMap (rbxassetid://114890052824249): value = clamp(0.42 + luminance × 1.15), tinted (232, 230, 222) |

The meshes are the generated ones (cloak 103044653642690, inner body 118804565624826) and the
stand-in rig's arms and hands, posed and scaled. New uploads need Roblox moderation before other
players see them.
