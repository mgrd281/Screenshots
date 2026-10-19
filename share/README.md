# Share links

Copy Link, in a photo's menu, uploads the copy that leaves the line here and
copies its link. This folder is the service behind it, on the owner's
Cloudflare account:

- `worker.js`: the Worker. `POST /api/files` takes a picture, a film or a
  PDF (up to 95 MB, twenty uploads a minute from one address) and answers
  with its link and a delete token; `/<id>` is the link's page, `/<id>/file`
  the file, `DELETE /api/files/<id>` with the token takes it down. A link
  stops working seven days after its upload.
- `wrangler.toml`: the Worker's settings, its R2 bucket `snapfly-share` and
  its rate limit.
- `worker.test.mjs`: its tests, `node --test share/worker.test.mjs`.

## Setting it up, once

The owner, in a browser:

1. Make a free Cloudflare account, and turn on R2 in its dashboard (it asks
   for a card, but the free part covers 10 GB).
2. Make an API token from the template "Edit Cloudflare Workers", and copy
   the Account ID from the dashboard.
3. Paste them in GitHub as the repository secrets `CLOUDFLARE_API_TOKEN` and
   `CLOUDFLARE_ACCOUNT_ID`.
4. Run the **Share Links** workflow by hand once. It makes the bucket, its
   rule that deletes every file after seven days and a workers.dev address,
   and deploys the Worker.

From then on, every build asks Cloudflare for the Worker's address
(`scripts/share-url.sh`) and puts it in Info.plist as `SnapflyShareURL`; Copy
Link is in the app only when it is there.
