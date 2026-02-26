# FlameBot website

This is a static website with:

- `index.html` (front page / marketing)
- `download/index.html` (downloads + setup)

## Deploy options

- Cloudflare Pages (drag & drop or connect a Git repo)
- GitHub Pages
- Railway (connect a Git repo and deploy the `website/` folder)

## Local preview

From the `website/` folder:

- `python -m http.server 5173`
- Open `http://localhost:5173`

Note: the Windows `py` launcher may not be installed on some PCs. If `py` fails, use `python`.

## Railway deploy (simple)

This repo includes `website/package.json` so Railway can deploy the site as a small Node web service.

1) Railway: **New Project** -> **Deploy from GitHub repo**
2) In the service settings, set **Root Directory** to `website`
3) Railway will run `npm install` and then `npm start`
4) Once deployed, open the Railway-provided URL

### Security headers (recommended)

This site is static, but it is deployed on Railway as a Node service so we can send security headers.

- The HTTP headers are set by `server.js` (CSP, HSTS on HTTPS, anti-framing, etc.)
- The `website/_headers` file is included for hosts like Cloudflare Pages/Netlify, but Railway does not apply it automatically.

## What to upload

- Build output zips:
	- `..\\dist\\FlameBot-Windows.zip`
	- `..\\dist\\FlameBot-macOS.zip`

## Screenshots (optional)

To show the in-page preview gallery, add 3 screenshots here:

- `website/assets/screenshots/screen-1.png`
- `website/assets/screenshots/screen-2.png`
- `website/assets/screenshots/screen-3.png`

If any are missing, the gallery auto-hides those items (and hides the section if none exist).

Note: screenshots are shown on `/download/` (backed by `download/index.html`).

## Recommended hosting (simple)

1) Create a GitHub repository and push this project.
2) On GitHub: Releases -> New release
3) Upload `dist/FlameBot-Windows.zip` and `dist/FlameBot-macOS.zip` as release assets.
4) Use this URL format on the website:

`https://github.com/Emperorgeneral/FLAMEBOT/releases/latest/download/FlameBot-Windows.zip`

`https://github.com/Emperorgeneral/FLAMEBOT/releases/latest/download/FlameBot-macOS.zip`

Update the Windows download link in `index.html` to point to wherever you host that zip (GitHub Release asset URL, S3/R2 public URL, etc.).