#!/bin/zsh
# ------------------------------------------------------------------
# 産学連携サイト：先生方の編集を確認して公開するためのツール
#
#   Finder でこのファイルをダブルクリックすると実行されます。
#   OneDrive（先生方の作業場所）と Git（公開される正本）の間をつなぎます。
# ------------------------------------------------------------------
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$HOME/Library/CloudStorage/OneDrive-筑波技術大学・天久保/産学連携サイト編集"

# 先生方が触るファイルだけを対象にする
# ※ rsync は先に書いた条件が優先されるため、除外を先に並べること
FILTER=(
  --exclude=".*"                 # .git など隠しファイル
  --exclude="style-guide.html"   # 内部資料
  --exclude="_config.yml" --exclude="CNAME"
  --exclude="tools/***"          # このツール自身
  --exclude="*.tif" --exclude="*.tiff"   # 写真の元データ（数十MBあるため配らない）
  --include="*.html"
  --include="styles.css"
  --include="images/"
  --include="images/**"
  --exclude="*"                  # 上記以外はすべて対象外
)

line(){ printf '%s\n' "------------------------------------------------------------"; }
git_(){ git -C "$REPO" "$@"; }

# 変更されたページを、ファイル名ではなく日本語の題名で並べる
# 戻り値 0 = 変更あり、1 = 変更なし
# 先生方が編集しうるファイルだけを見る（ツール自体の変更は対象外）
changed_files(){
  git -C "$REPO" -c core.quotepath=false status --porcelain -- \
    '*.html' 'images' ':!tools' ':!editor.html' | awk '{print $NF}'
}

show_changes(){
  local files t
  files=$(changed_files)
  if [ -z "$files" ]; then
    echo "  変更はありません。"
    return 1
  fi
  while read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *.html)
        t=$(grep -o '<title>[^<]*' "$REPO/$f" 2>/dev/null | head -1 | sed 's/<title>//' | cut -d'｜' -f1)
        printf '  ・%s\n      (%s)\n' "${t:-$f}" "$f"
        ;;
      images/*) printf '  ・写真： %s\n' "${f#images/}" ;;
      *)        printf '  ・%s\n' "$f" ;;
    esac
  done <<< "$files"
  return 0
}

distribute(){
  mkdir -p "$WORK"
  rsync -a "${FILTER[@]}" "$REPO/" "$WORK/"
  cp "$REPO/editor.html" "$WORK/editor.html"
  # 案内に載せる連絡先は、公開リポジトリに含めず手元のファイルから読む
  # （tools/連絡先.txt は .gitignore 済み。無い場合は差し込まない）
  local contact="担当教員"
  [ -f "$REPO/tools/連絡先.txt" ] && contact=$(head -1 "$REPO/tools/連絡先.txt")
  sed "s|__CONTACT__|$contact|g" \
    "$REPO/tools/はじめにお読みください.html" > "$WORK/はじめにお読みください.html"
}

echo ""
line
echo "  産学連携サイト  編集の確認と公開"
line

if [ ! -d "$REPO/.git" ]; then
  echo "！ Git リポジトリが見つかりません。処理を中止します。"
  echo ""; read -r "?Enter キーで閉じます"; exit 1
fi

while true; do
  echo ""
  echo "  1) 先生方の変更を取り込む   OneDrive の編集内容を手元に持ってくる"
  echo "  2) 変更内容を詳しく見る     どこがどう変わったかを表示する"
  echo "  3) 公開する                 GitHub に送ってサイトに反映する"
  echo "  4) 変更を取り消す           取り込んだ内容を破棄して元に戻す"
  echo "  5) 最新のサイトを配る       Git の内容を OneDrive へ配布する"
  echo "  6) 終わる"
  echo ""
  read -r "choice?  番号を入れて Enter： "
  echo ""

  case "$choice" in
    1)
      if [ ! -d "$WORK" ]; then
        echo "！ OneDrive 側のフォルダがありません。先に「5) 最新のサイトを配る」を実行してください。"
      else
        echo "▶ OneDrive から取り込んでいます…"
        # editor.html は配布専用（先生方の編集対象ではない）ので戻さない
        rsync -a --exclude="editor.html" --exclude="はじめにお読みください.html" \
          "${FILTER[@]}" "$WORK/" "$REPO/"
        echo ""
        line
        echo "  変更されたページ"
        line
        show_changes
        echo ""
        echo "  → 内容を見るには 2、公開するには 3、やめるには 4 を選んでください。"
      fi
      ;;
    2)
      if ! show_changes >/dev/null; then
        echo "  取り込まれた変更はありません。"
      else
        echo "▶ 変更部分を表示します（q で戻ります）"
        echo ""
        git_ diff --color-words -- '*.html' | less -R
        echo ""
        read -r "openq?  変更されたページをブラウザで確認しますか？ (y/n)： "
        if [ "$openq" = "y" ]; then
          changed_files | grep '\.html$' | while read -r f; do
            open "$REPO/$f"
          done
        fi
      fi
      ;;
    3)
      if ! show_changes; then
        echo "  公開できる変更がありません。"
      else
        echo ""
        read -r "msg?  変更内容をひとことで（空欄なら「先生方による編集の反映」）： "
        [ -z "$msg" ] && msg="先生方による編集の反映"
        echo ""
        read -r "ok?  この内容で公開します。よろしいですか？ (y/n)： "
        if [ "$ok" = "y" ]; then
          git_ add -A
          git_ commit -q -m "$msg"
          if git_ push origin main; then
            echo ""
            echo "✓ 公開しました。数分でサイトに反映されます。"
            echo "▶ 最新の内容を OneDrive にも配ります…"
            distribute
            echo "✓ 配布しました。"
          else
            echo ""
            echo "！ 送信に失敗しました。ネットワークをご確認ください。"
            echo "   （変更は手元に保存されています。もう一度 3 を選べば再送できます）"
          fi
        else
          echo "  公開しませんでした。"
        fi
      fi
      ;;
    4)
      if ! show_changes; then
        echo "  取り消す変更はありません。"
      else
        echo ""
        read -r "ok?  取り込んだ変更をすべて破棄します。よろしいですか？ (y/n)： "
        if [ "$ok" = "y" ]; then
          git_ checkout -- .
          git_ clean -fd -- '*.html' images >/dev/null 2>&1
          echo "✓ 元に戻しました。"
          echo "  ※ OneDrive 側は変更されたままです。先生方に修正を依頼するか、"
          echo "     5 で最新のサイトを配り直してください。"
        else
          echo "  そのままにしました。"
        fi
      fi
      ;;
    5)
      echo "▶ Git の内容を OneDrive へ配っています…"
      distribute
      echo "✓ 配布しました。OneDrive の同期が終わるまで少しお待ちください。"
      ;;
    6|"")
      echo "終わります。"
      break
      ;;
    *)
      echo "1〜6 の番号を入れてください。"
      ;;
  esac
done

echo ""
read -r "?Enter キーで閉じます"
