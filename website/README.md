# FlameBot download page

This is a minimal static download page.

## Deploy options

- Cloudflare Pages (drag & drop or connect a Git repo)
- GitHub Pages
- Railway (connect a Git repo and deploy the `website/` folder)

## What to upload

- Build output zip: `..\\dist\\FlameBot-Windows.zip`

## Recommended hosting (simple)

1) Create a GitHub repository and push this project.
2) On GitHub: Releases -> New release
3) Upload `dist/FlameBot-Windows.zip` as a release asset.
4) Use this URL format on the website:

`https://github.com/OWNER/REPO/releases/latest/download/FlameBot-Windows.zip`

Replace `OWNER/REPO` with your repo.

Update the Windows download link in `index.html` to point to wherever you host that zip (GitHub Release asset URL, S3/R2 public URL, etc.).
