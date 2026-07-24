# forgepeek 3D page emitter — sourced by the iframe-mode handlers (stl, fbx).
# Emits one complete, self-contained HTML document: inline CSS, the committed
# three.js bundle (lib/viewer.js), and the model bytes as base64 decoded
# client-side. Nothing is fetched at view time.
#
# The container carries an explicit height (70vh, min 480px): Forgejo sizes
# the sandboxed iframe from the page's reported scrollHeight (PR #8378), and
# an explicit height is the belt-and-suspenders against the historic
# zero-height iframe problem.

fp_3d_page_head() {
    cat <<'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; }
  #forgepeek {
    position: relative;
    width: 100%;
    height: 70vh;
    min-height: 480px;
    overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }
  #forgepeek canvas { display: block; }
  .fp-hud {
    position: absolute;
    top: 8px;
    left: 8px;
    display: flex;
    gap: 8px;
    align-items: center;
    font-size: 12px;
    color: #57606a;
    background: rgba(246, 248, 250, 0.85);
    border: 1px solid #d0d7de;
    border-radius: 6px;
    padding: 4px 8px;
  }
  .fp-hud button {
    font: inherit;
    color: inherit;
    background: transparent;
    border: 1px solid #d0d7de;
    border-radius: 4px;
    padding: 2px 8px;
    cursor: pointer;
  }
  .fp-hud button:hover { background: #eaeef2; }
  .fp-hud button.fp-on { background: #ddf4ff; border-color: #54aeff; }
  .fp-box {
    border-radius: 6px;
    padding: 12px 16px;
    margin: 8px;
    font-size: 14px;
  }
  .fp-box p { margin: 0; }
  .fp-box-title { font-weight: 600; margin-bottom: 4px !important; }
  .fp-error  { border: 1px solid #d1242f; background: #fff5f5; color: #24292f; }
  .fp-notice { border: 1px solid #d0d7de; background: #f6f8fa; color: #24292f; }
  @media (prefers-color-scheme: dark) {
    body { background: #161b22; }
    .fp-hud {
      color: #8b949e;
      background: rgba(22, 27, 34, 0.85);
      border-color: #30363d;
    }
    .fp-hud button { border-color: #30363d; }
    .fp-hud button:hover { background: #21262d; }
    .fp-hud button.fp-on { background: #0c2d6b; border-color: #1f6feb; }
    .fp-error  { background: #2d1214; border-color: #f85149; color: #e6edf3; }
    .fp-notice { background: #161b22; border-color: #30363d; color: #e6edf3; }
  }
</style>
</head>
<body>
<div id="forgepeek"></div>
<script>
EOF
    cat "$FORGEPEEK_LIB/viewer.js"
    printf '</script>\n'
}

# fp_3d_page FORMAT MODEL_FILE — full page with the model embedded.
fp_3d_page() {
    fp_3d_page_head
    printf '<script>ForgePeekViewer.init({format:"%s",data:"' "$1"
    fp_b64 "$2"
    printf '"});</script>\n</body>\n</html>\n'
}

# fp_3d_page_too_large FORMAT ACTUAL_BYTES LIMIT_BYTES — the "too large"
# notice is rendered by the viewer page's own JS so it is styled like every
# other viewer message.
fp_3d_page_too_large() {
    fp_3d_page_head
    printf '<script>ForgePeekViewer.init({format:"%s",tooLarge:{sizeMB:"%s",limitMB:"%s"}});</script>\n</body>\n</html>\n' \
        "$1" "$(fp_mb "$2")" "$(fp_mb "$3")"
}
