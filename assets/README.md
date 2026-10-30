# Assets

The images in the main README come from the PietroDispatch generators, driven from the Pietro.works design standard (dark mode, DM Mono labels, one accent moment per view).

| File | Generator | Canvas |
| :--- | :--- | :--- |
| `hero-workflow.webp` | article cover renderer | 1920x1080 |
| `change-loop.webp`, `pacs.webp`, `context.webp`, `humanize-md.webp` | fluxogram renderer | 2400x822 |

All five are downscaled to 1600 px wide webp. The spec behind each one is in [`src/`](src), with the background named by its file in the shared background library. No image-generation call was involved, only the library backgrounds and a headless browser.
