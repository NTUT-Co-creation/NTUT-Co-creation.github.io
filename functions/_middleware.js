// Cloudflare Pages 用の簡易パスワード認証（学内レビュー用）
// すべてのリクエストの前に実行され、Basic認証でパスワードを要求します。
// パスワードは Cloudflare の環境変数 PREVIEW_PASSWORD に設定してください
// （コードには書きません）。ユーザー名は何でもOK、パスワードだけ照合します。
//
// ※ この仕組みは Cloudflare Pages でのみ有効です。GitHub Pages では動作しません
//   （GitHub Pages は静的配信のみ）。GitHub Pages 側は _config.yml の exclude で
//   この functions フォルダを配信対象から外しています。

export async function onRequest(context) {
  const { request, env, next } = context;
  const expected = env.PREVIEW_PASSWORD;

  // 環境変数が未設定なら誤って全公開しないよう停止
  if (!expected) {
    return new Response(
      "PREVIEW_PASSWORD が設定されていません（Cloudflare の環境変数を設定してください）。",
      { status: 500, headers: { "content-type": "text/plain; charset=utf-8" } }
    );
  }

  const header = request.headers.get("Authorization") || "";
  if (header.startsWith("Basic ")) {
    try {
      const decoded = atob(header.slice(6));        // "user:pass"
      const pass = decoded.slice(decoded.indexOf(":") + 1);
      if (pass === expected) {
        return next();                               // 認証OK → サイトを表示
      }
    } catch (e) { /* 不正なヘッダは下の401へ */ }
  }

  return new Response("このサイトは学内レビュー用です。パスワードを入力してください。", {
    status: 401,
    headers: {
      "WWW-Authenticate": 'Basic realm="NTUT 産学連携プロジェクト（学内レビュー）"',
      "content-type": "text/plain; charset=utf-8",
    },
  });
}
